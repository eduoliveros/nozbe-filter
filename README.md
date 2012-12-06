Nozbe Filter
=============

This is a Perl program (using `wxPerl` / `wxWidgets` for the user interface) that allows 
filtering of tasks of the Nozbe.com website.

I have programmed and used it in a Mac, but should work in all OS.

Installation
-------------
There are several CPAN modules that should be installed to be able to run the application.
    Data::Dumper
    Array::Utils
    LWP::Simple
    JSON
    Wx 

To know what modules are not installed try to run the application:
    perl nozbe_tasks_filter.pl

To install those modules you have to execute:
    sudo perl -MCPAN -e shell

    cpan[1]> install ModuleName:Here
    cpan[2]> exit

If you are using Mac, more probably you will need XCode (free, today is free:)) and 
download the "Command Line Tools", some help here:
(https://developer.apple.com/xcode/)
 XCode -> Preferences...
 Downloads (section on the top)
 Components
 Command Line Tools [install button]


Configuration
-------------

The only configuration required is to include your Nozbe API key in $key (at the 
beginning of the file). You can get this key going to your account information in 
Nozbe.com.

BTW, I don't have any relation with Nozbe.com, I'm only using its public API.
http://webapp.nozbe.com/api


License
-------
what? :), well... please, use it for the good of humanity.

