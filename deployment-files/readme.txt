
Readme for Tagger
=================
Copyright (c) 2008-2009 Ali Rantakari
http://hasseg.org/tagger


DESCRIPTION:
------------

Tagger is a small application for OS X that can be used for quickly
adding arbitrary textual tags to files. It uses the OpenMeta
tagging system, so it is compatible with all other applications
that support OpenMeta.


Tagger is a Universal Binary and requires Mac OS 10.5 or later.
It includes "NSImage+QuickLook" code by Matt Gemmell.


USAGE:
------

You tell Tagger which file you want to tag when launching it.
There are several ways to do this:

* Simply launch Tagger when the frontmost application window
  is a document window
    If the currently active window in whichever application you're
    using is a Cocoa document window, Tagger will, when launched,
    let you tag that document. This way, you can use whichever
    quick way of launching Tagger you would prefer (Spotlight,
    Quicksilver or LaunchBar, for example, or a global hotkey via
    Spark, Keyboard Maestro or some other similar application.)
    NOTE: This feature requires you select the "Enable access
    for assistive devices" option in the "Universal Access"
    preference pane in System Preferences.

* Select files in Finder or Path Finder, then launch Tagger
    You can simply let Tagger ask Finder or Path Finder (whichever
    is the frontmost application at the time of launching Tagger)
    for the currently selected files when it launches and let you
    tag them. This way, you can use whichever quick way of launching
    Tagger you would prefer (Spotlight, Quicksilver or LaunchBar,
    for example, or a global hotkey via Spark, Keyboard Maestro or
    some other similar application.)

* Drag & drop
    If you drag & drop files on top of Tagger, it will launch and
    let you tag those files.

* Command-line argument
    If you would prefer to launch Tagger via the command line (a
    shell script, for example,) you can specify the files to tag
    with the -f argument. If you wish to specify more than one file,
    separate their paths with a newline. An example:
    
    $ /path/to/Tagger.app/Contents/MacOS/Tagger -f "/path/to/a file to tag
    /path/to/another file
    /some/third/file"

When you're done editing the tags, commit your changes by either
clicking on the "Ok" button or by pressing Command-Return when the
focus is in the tags field. You can quit Tagger (and discard any
changes you've made) by pressing Esc or Command-Q, or by closing the
window.

To search for files by their tags, you can simply type "tag:tagname"
into Spotlight. So for example: "tag:todo"



LICENSE:
--------

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA  02110-1301, USA.




