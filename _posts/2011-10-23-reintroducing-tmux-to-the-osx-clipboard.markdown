---
layout: post
title: Re-introducing tmux to the osx clipboard
---

__TL;DR__ - Copying text from tmux is broken in OSX.  A workaround is
introduced along with a clean way of shimming it in to your setup.  Here's the
obligatory "I don't care how it works just give me something I can blindly run
to fix it" snippet:

{% codesnippet bash invert_colors noexpando %}
formula_url=https://raw.github.com/phinze/homebrew/tmux-macosx-pasteboard/Library/Formula/reattach-to-user-namespace.rb
brew install $formula_url --wrap-pbcopy-and-pbpaste
{% endcodesnippet %}


----

Doing software development on an OSX machine means living with a weird set of parents.

<div class="figure">

<img style="height: 200px;" src="/img/jonathan-ive.jpg" />
+
<img style="height: 200px;" src="/img/kernighan.jpg" />
=
<img style="width: 200px;" src="/img/TuxOSX.png" />

</div>

You've got your mother---Apple---all curves and style, and your father---UNIX---all
sharp angles and beards.  That penguin does look sort of uncomfortable all crammed
in there, doesn't he?

I hate it when mommy and daddy fight.  It only hurts the children, who just
want to be able to copy text from inside a tmux session.

### What's broken

If you've ever used `tmux` -- the delightful little GNU screen replacement --
on OSX, you may have run into an annoying little problem.  The handy `pbcopy`
and `pbpaste` commands that normally give access to the OSX clipboard
mysteriously stop working from within tmux.

This leaves you CMD+option clicking to box select and copy in iTerm and then
dealing with your paste including any trailing whitespace from the box you
made.  Annoying and inconvenient.

### Why it's broken

GitHub user `ChrisJohnsen` has done a great job of researching and explaining
what's happening here.  I will defer to [his awesome in-depth
explanation](https://github.com/ChrisJohnsen/tmux-MacOSX-pasteboard) of both
the problem and his solution, which is at the core of our workaround.

### Getting the fix in place

In order to make it easy to install, I've created a homebrew formula that will
download and compile the `reattach-to-user-namespace` tool.

You can install it like so:

{% codesnippet console invert_colors noexpando %}
phinze:~$ brew install https://raw.github.com/phinze/homebrew/tmux-macosx-pasteboard/Library/Formula/reattach-to-user-namespace.rb
{% endcodesnippet %}

So ChrisJohnsen recommends setting the `reattach-to-user-namespace` command to
wrap every shell session under tmux using it's `default-command` option.  This
works perfectly fine, but I found that I didn't like having a parent process
execute every time I made a new `tmux` window or split.  I really only want
`pbcopy` and `pbpaste` to work again, so I'm content just wrapping those
commands.

To make this simple, I've added a `--wrap-pbcopy-and-pbpaste` option to my formula
which creates little shims in `/usr/local/bin` that look like this:

{% codesnippet bash invert_colors noexpando %}
#!/bin/sh
cat - | reattach-to-user-namespace /usr/bin/pbcopy
{% endcodesnippet %}

{% codesnippet bash invert_colors noexpando %}
#!/bin/sh
reattach-to-user-namespace /usr/bin/pbpaste
{% endcodesnippet %}

With these in place I'm perfectly content and back to my usual clipboard-piping ways.

### What about other apps like vim?

The `reattach-to-user-namespace` utility can be wrapped around any binary that
has become lost from the OSX clipboard for the same reasons.  For example,
wrapping this around `vim` will fix the `+` register to once again point to the
system clipboard.  Again, you could go so far as to use `ChrisJohnsen`'s
recommendation of wrapping all your shell sessions with the command, but I've
found it cleaner to just apply it judiciously to the affected area.

### Inclusion in mxcl/homebrew

I've got myself a pull request submitted to the homebrew project proper, hopefully
they'll consider accepting it.  That would make installing this as easy as
`brew install reattach-to-user-namespace`.  It's not exactly a shoe-in for inclusion
in the main homebrew repository, but I've included some justification on the
description of the pull request.

[https://github.com/mxcl/homebrew/pull/8016](https://github.com/mxcl/homebrew/pull/8016)

If you think this would be useful to you, consider posting a "+1" comment to this thread.

However the pull request pans out, I'll keep my branch up, since I'll be using
this workaround until a better solution turns up.
