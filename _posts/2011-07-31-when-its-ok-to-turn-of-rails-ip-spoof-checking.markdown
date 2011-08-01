---
layout: post
title: Rails may be silently dropping legitimate requests to your app
---

__TL;DR__ - Rails' "IP spoof checking" has an overly-drastic policy of
completely blowing up when things don't look right.  We follow the
investigation of an exception caused by this check, learn about IP spoofing
generally, and implement a middleware-based solution that retains the security
aspects of the check without dropping requests.

----

When tracking down some stray `500`s in an application at work, I started
investigating messages like the following:

    /!\ FAILSAFE /!\  Sat May  11:12:54 -0400 2008
      Status: 500 Internal Server Error
      IP spoofing attack?!
    HTTP_CLIENT_IP="11.22.33.44"
    HTTP_X_FORWARDED_FOR="33.44.55.66, 23.12.34.123"

So let's break this down.

### What's a Failsafe?

Anything that hits the failsafe in Rails is generally Very Bad, because it
means all of your normal in-app exception handling (e.g. an exception notifier
that sends your team an email) is not running.  It's implemented as a Rack
middleware that sits at the top of the stack and rescues any exceptions raised
further down:

{% codesnippet ruby linenos linenostart=25 githublink=rails/rails/blob/v2.3.11/actionpack/lib/action_controller/failsafe.rb#L25-34 %}
def call(env)
  @app.call(env)
rescue Exception => exception
  # Reraise exception in test environment
  if defined?(Rails) && Rails.env.test?
    raise exception
  else
    failsafe_response(exception)
  end
end
{% endcodesnippet %}

So somehow an exception has bubbled up the Rack stack to this layer, causing
the failsafe handler to print it to the log with those cute little ascii
caution signs.  Well that's definitely not good...

### What causes this exception?

Now we know that the IP spoof exception is coming from somewhere outside of
normal application code.  Luckily the message is pretty easy to grep for in the
Rails source (thanks for using a "?!" guys), which brings us to this code:

{% codesnippet ruby linenos linenostart=228 githublink=rails/rails/blob/v2.3.11/actionpack/lib/action_controller/request.rb#L228-241 %}
remote_ips = @env['HTTP_X_FORWARDED_FOR'] && @env['HTTP_X_FORWARDED_FOR'].split(',')

if @env.include? 'HTTP_CLIENT_IP'
  if ActionController::Base.ip_spoofing_check && remote_ips && !remote_ips.include?(@env['HTTP_CLIENT_IP'])
    # We don't know which came from the proxy, and which from the user
    raise ActionControllerError.new(<<EOM)
IP spoofing attack?!
HTTP_CLIENT_IP=#{@env['HTTP_CLIENT_IP'].inspect}
HTTP_X_FORWARDED_FOR=#{@env['HTTP_X_FORWARDED_FOR'].inspect}
EOM
  end

  return @env['HTTP_CLIENT_IP']
end
{% endcodesnippet %}

Lines 228-231 are the key.  If `HTTP_CLIENT_IP` shows up in the Rack
environment, it must also show up in the `remote_ips` array, or else we blow
up.  The former is set by the `Client-IP` header on the incoming request,
and you can see on 228 that `remote_ips` is set by splitting the
`X-Forwarded-For` header on commas.  So an exception is raised if the IP
specified in the `Client-IP` header of the request is not found in the list
provided in the `X-Forwarded-For` header.

### But why papi?

We now see what the code does, but what's the context here?  Why does Rails
choose to freak out if these two headers are present and don't match?  We have
to understand how these two headers are used.

Both of these headers are non-standard ways of solving the same basic problem:
web proxies mask the source IP address of traffic that bounces through them,
but web applications still have good reasons for wanting to know the original
source IP of incoming requests.

Why two non-standard headers?  Well, _because
there isn't a standard_.  Some web proxies just started adding an extra HTTP
header to indicate the IP address of the original client.  Squid went with a
header called `X-Forwarded-For` which stores a list of IP addresses as an HTTP
request is forwarded along.

The `Client-Ip` header is essentially the same story, with the exception that
it seems to be specced to hold just the original source IP address, so proxies
can't tack on additional IPs as they pass the traffic along.  From what I've
found it seems that you'll see `Client-IP` headers more often when dealing with
mobile traffic and Flash clients.

### Reproducing in Rails 2.3

It looks like this exception should be pretty easy to reproduce.  We just need to
pass in bogus `Client-Ip` and `X-Forwarded-For` headers that don't match and
watch everything explode.

First we'll build up a clean project with a super-basic scaffold.

{% codesnippet console invert_colors %}
phinze:/tmp$ rvm use 1.9.2@ipspoof-twothree --create
phinze:/tmp$ gem install rails -v 2.3.11 && gem install sqlite3
phinze:/tmp$ rails ipspoof-twothree && cd ipspoof-twothree
phinze:/tmp/ipspoof-twothree$ ./script/generate scaffold SomeModel
phinze:/tmp/ipspoof-twothree$ rake db:migrate
phinze:/tmp/ipspoof-twothree$ ./script/server
=> Rails 2.3.11 application starting on http://0.0.0.0:3000 (...)
{% endcodesnippet %}

With the server running, we'll cook up a simple request with telnet:

{% codesnippet console invert_colors %}
phinze:~$ telnet 127.0.0.1 3000
GET /some_models HTTP/1.1
Client-IP: 1.2.3.4
X-Forwarded-For: 2.3.4.5

HTTP/1.1 500 Internal Server Error
...
{% endcodesnippet %}

Boom.  There we go.  So let's check the logs.

{% codesnippet console invert_colors %}
phinze:/tmp/ipspoof-twothree$ grep -A 4 'FAILSAFE' log/development.log
/!\ FAILSAFE /!\  2011-07-30 12:27:18 -0500
  Status: 500 Internal Server Error
    IP spoofing attack?!
    HTTP_CLIENT_IP="1.2.3.4"
    HTTP_X_FORWARDED_FOR="2.3.4.5"
{% endcodesnippet %}

Bingo!  We've now isolated this problem in a barebones context, proving
that this isn't some weird error being cause by app code.

### The thrilling conclusion

While we've gone over the problem at the lowest layer, an important question
remains: where is `remote_ip` being called?  That answer can be easily gleaned
from the backtrace in our log, which leads us to the eye-rolling cause of this
whole rigmarole:

{% codesnippet ruby linenos linenostart=1312 githublink=rails/rails/blob/v2.3.11/actionpack/lib/action_controller/base.rb#L1312-1318 %}
def log_processing_for_request_id
  request_id = "\n\nProcessing #{self.class.name}\##{action_name} "
  request_id << "to #{params[:format]} " if params[:format]
  request_id << "(for #{request_origin}) [#{request.method.to_s.upcase}]"

  logger.info(request_id)
end
{% endcodesnippet %}

Yep.  That call to `request_origin` is what blows up our entire request, as
Rails attempts to get the source IP address for the _log_.  No wonder we're
outside of in-app exception handlers.

### Well that's stupid, can we turn it off?

In reaction to this conclusion, a bit of an argument erupted between two of the many
small people living in my head: __High-Availability Hank__ and
__Security-Minded Sally__.

Hank
:  Ack! So Rails is completely failing to serve a request just because it comes
   in with a bad `Client-IP` header?

Sally
:  Yes, because the request might be fraudulent and we don't want our service
   to take any action that's not verified.

Hank
:  Sure, but we might be dropping real requests from mis-configured clients!
   That's Very Bad!

Sally
:  True, but accepting malicious traffic is also Very Bad!

Paul
:  Guys, guys! There's got to be a compromise here.  Look, HAProxy will assign
   `X-Forwarded-For` based on the actual IP address it gets from the client TCP
   connection.  Can't we ignore everything else and use that?

Sally
:  I suppose so long as you strip other headers, we'll be able to trust the
   `remote_ip` implementation, since it will always pull from `X-Forwarded-For`.

Hank
:  And if you can turn off IP spoof checking, Rails won't blow up at the drop of a hat.

Paul
:  Awesome, so at the Rails layer we'll drop the `Client-Ip` header completely
   and trust `X-Forwarded-For`, since we'll configure HAProxy to set it
   properly for us.  Like this:

{% codesnippet ruby linenos %}
class IpSpoofProtectionMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(_strip_ip_spoofable_headers(env))
  end

  def _strip_ip_spoofable_headers(env)
    env.reject { |key, value| key.upcase == 'HTTP_CLIENT_IP' }
  end
end
{% endcodesnippet %}

Then we'll turn off IP spoof checking in ActionController with this line in
`config/environment.rb`:

{% codesnippet ruby %}
config.action_controller.ip_spoofing_check = false
{% endcodesnippet %}

This isn't technically required, since we're stripping the header that would
cause this check to raise an exception, but based on the boom boom policy baked
into the check, it seems better to get the whole code path out of the way.

### The whole story, in bullet points.

* Track down a stray 500.
* Learn about Rails FAILSAFE.
* Dig through IP Spoof checking code.
* Research the `X-Forwarded-For` and `Client-Ip` headers.
* Reproduce the exception in a fresh Rails project.
* Realize the whole request blogs up because of logging.
* Decide this is silly, wonder how to turn it off.
* Implement an equivalent concept as a Rack middleware.

### Should Rails change?

In Rails 3 the same `remote_ip` code exists, but the logs don't attempt to
include the client IP address, so there's no FAILSAFE explosion.  I still
believe that the strategy of raising an exception when these two headers don't
match is overly drastic, but I don't feel like I have a deep enough
understanding of all the factors involved to propose a change.

For now, this post can remain as documentation of my medium-level dive into the
topic, so I can hopefully pick up where I left off if the fancy ever strikes me
again.

### Watch for failsafes

Another quick but important takeaway from this is that you can't rely on an
exception notifier to catch every possible application-level error.  You need
to monitor at a higher level in order to detect anything that hits the Rails
failsafe.
