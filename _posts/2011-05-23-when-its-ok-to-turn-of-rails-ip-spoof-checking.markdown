---
layout: post
title: When it's okay to turn off Rails' IP spoof checking
---

When tracking down some stray 500s in our application, I started investigating
messages like the following:

    /!\ FAILSAFE /!\  Sat May  11:12:54 -0400 2008
      Status: 500 Internal Server Error
      IP spoofing attack?!
    HTTP_CLIENT_IP="67.195.44.101"
    HTTP_X_FORWARDED_FOR="67.195.44.101, 67.195.37.172"

Anything that hits the failsafe in Rails is generally Very Bad, because it
means all of your normal in-app exception handling is not running.  It's
implemented as a Rack middleware that sits at the top of the stack and rescues
any exceptions raised further down:

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

### Determining the Cause of the Error

So we know that the IP spoof exception is coming from somewhere outside of
normal application code.  Luckily the message is pretty easy to grep for in the
Rails source (thanks for using a "?!" guys), which  brings us to this code:

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
up.  The former is set by the the `Client-IP` header on the incoming request,
and you can see that `remote_ips` is set by splitting the `X-Forwarded-For`
header on commas.

### Gaining some Perspective

We now see what the code does, but what's the context here?  Why does Rails
choose to freak out if these two headers are present and don't match?

It looks like this issue should be pretty easy to reproduce.  We just need to
pass in bogus `Client-Ip` and `X-Forwarded-For` headers that don't match and
watch everything explode.

### Reproducing in Rails 2.3

First we'll build up a clean project with a super-basic scaffold.

{% codesnippet console invert_colors %}
phinze:/tmp$ rvm use 1.9.2@ipspoof-twothree --create
Using /Users/phinze/.rvm/gems/ruby-1.9.2-p180 with gemset ipspoof-twothree

phinze:/tmp$ gem install rails -v 2.3.11 && gem install sqlite3
Successfully installed rails-2.3.11
...

phinze:/tmp$ rails ipspoof-twothree && cd ipspoof-twothree
create  app/controllers
create  app/helpers
create  app/models
...

phinze:/tmp/ipspoof-twothree$ ./script/generate scaffold SomeModel
      create    app/models/some_model.rb
...

phinze:/tmp/ipspoof-twothree$ rake db:migrate
(in /private/tmp/ipspoof-twothree)
==  CreateSomeModels: migrating ===============================================
-- create_table(:some_models)
   -> 0.0009s
==  CreateSomeModels: migrated (0.0010s) ======================================

phinze:/tmp/ipspoof-twothree$ ./script/server
=> Booting WEBrick
=> Rails 2.3.11 application starting on http://0.0.0.0:3000
...
{% endcodesnippet %}

Now we're ready to test out our theory about how this can be reproduced.  With
the server running, we'll cook up a simple request with telnet:


{% codesnippet console invert_colors %}
phinze:~$ telnet 127.0.0.1 3000
Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.
GET /some_models HTTP/1.1
Client-IP: 1.2.3.4
X-Forwarded-For: 2.3.4.5

HTTP/1.1 500 Internal Server Error
...
{% endcodesnippet %}
