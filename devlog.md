# Repeater interpreter

In the past, I always saw the interpreter as magic; or at least the product of complex logical programming. When you dive into the guts of one, though, it turns out that the "magic" is quite simple (at least for simple interpreters). In this post we are going to build the simplest interpreter I could think of, that still gets us started in the right direction.

Meet the repeater interpreter running in a bash console:

```bash
$ ./repeater
Welcome to the simplest interpreter I could think of.

Usage: write some characters and press enter. Guess what´s next.
------------------------
>>> abc
abc
>>> Try this!
Try this!
>>> Stop repeating
Stop repeating
>>> quit
... quitting repeater
$
```

## Choosing an implementation language.

We will choose C++.

```c++
// file: repeater.cpp
#include <iostream>

int main() {
    std::cout << "Hello world" << std::endl;
}
```


## Character streams

All interpreters take in characters, process them somehow, and then they spit out something else. In this case, our interpreter will just spit out similar characters. Let's get that up and running.

There are various ways in C and C++ to get the input from a terminal.


> **[`std::cin`][see std::cin cppref]**
>
> Using [`std::cin`][see std::cin cppref] is the proper C++ way that uses streams (think `>>` operator). 

> **[`gets`][see gets cppref]**
>
> The C [`gets`][see gets cppref] function is a more "classical" approach.  

[see gets cppref]: https://en.cppreference.com/w/cpp/io/c/gets
[see std::cin cppref]: https://en.cppreference.com/w/cpp/io/cin
