

Documentation for Tagger's "Front Application Scripts" Feature
================================================================

*Front application scripts* is a feature that allows you to use custom AppleScripts for pairing Tagger up with any application that supports AppleScript. The purpose is to __enable Tagger to ask different applications for files to tag__ (it always asks the frontmost application, when launched, for files to tag *if* it has built-in support for this particular application, *or if* you've added a *Front application script* for this app).



Installing Scripts
--------------------

You can __install ready-made scripts__ from Tagger's online repository:

 - Select *Tagger &rarr; Manage Front Application Scripts...* from Tagger's menu.
 - Select the *Get More Scripts* tab
 - Choose a script from the list, check out its description and press *Install*

After this, you'll be able to launch Tagger with the application you just installed a script for at the front (possibly with some items selected), and Tagger will let you tag those items.



Installing Existing Scripts Manually
--------------------------------------

If you have an existing front application script and you'd like to use it, you just need to open Tagger and __drag the script file onto Tagger's main window__. Tagger will then ask you to enter the identifier or name of the application that this script was written for. When you've entered this, simply press *Add Script* and you're done.

You can also do this manually by copying the AppleScript file into the Scripts folder (`~/Library/Application Support/Tagger/Scripts/`) and adding an entry into the Catalog file (`~/Library/Application Support/Tagger/Scripts/Catalog.plist`) for it, with the identifier of the application as key and the file name of the script as value.



Writing new Scripts
---------------------

If you'd like to __write a front application script__ for an application, you just need to make sure that your script returns the correct kind of data to Tagger. What Tagger wants is a record with one of these two fields (i.e. not both):

- `filePaths` (containing _a list of full paths_ to the files to tag)
- `webLinks` (containing _a list of records_ each of which should have the fields `link` (a URL string) and `title` (the title for the document that the link points to -- if the link points to a web page, this should be the title of that web page))

This record may also contain the field `title`, which, if included, will specify what title to display in place of the tagged filename(s).

_Example #1: Return paths to two files and a custom title_

    return {filePaths: {"/path/to/file1.ext",
                        "/path/to/file2.ext"},
            title: "2 SuperExtra App Documents"
           }

_Example #2: Return two web links_

    return {webLinks: {{link:"http://hasseg.org",
                        title:"Hasseg site"},
                       {link:"http://hasseg.org/tagger",
                        title:"Tagger site"}
                      }
           }

Also, any error messages a script throws will be shown to the user. For example:

    error "Can not get selection due to solar radiation"

An example script for iTunes is included in the Tagger distribution package, along with a `Catalog.plist` file that contains an entry for this script.

If you've written a fully working script for an application that isn't in the online repository, __you can [send it to me](http://hasseg.org)__ and I'll put it there.



