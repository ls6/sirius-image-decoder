What is this file?
------------------

This is (executable) explanation of how sirius server encodes images for
“little printers”. I wrote it as a “literate program” so *all* the code
is in this document. Details in the [Addendum](#addendum).

This project is hosted
here:<https://github.com/ls6/sirius-image-decoder>

If you are new to this “little printer” thing, the best starting point
to the whole idea is at <https://tinyprinter.club>

On the programming language used here
-------------------------------------

It is Tcl because it gave me the easiest path to experiment with putting
dots on my screen. The advantage for you is that you can play with this
on any platform without installing anything. Just find a `tclkit` for
your platform and use it to run this program interactively.

You don’t have to, though :)  
I hope just reading through this file will help you. I tried to keep the
code simple and relatively free of Tcl’s idiosyncracies.

Anyway, if you want to poke around, Make sure you get a Tclkit with Tk
(graphics support) included. You can configure and download one yourself
here: <http://kitcreator.rkeene.org/kitcreator>  
I’ve just checked: it works. I’m using it when writing this :)  
Once you have the kit (or installed Tcl and Tk on your system) open the
tcl prompt and type:  
`source sirius-image-decoder.tcl`  
and then:  
`help`

A big disclaimer about this code: it is *exploratory* code I wrote in
order to understand how these images are encoded. Without any changes
this code is *bad for “production use”*, it is memory hungry, no errors
are checked, everything is assumed to work…

<a name='spec'>What exctly are we trying to figure out? </a>
------------------------------------------------------------

The sirius server implemenation
[says](https://github.com/nordprojects/sirius/blob/6c6f8e9fe5e1552df180213007226331ca279db9/sirius/coding/image_encoding.py#L27)
this:

> so what we have is a list of runs, alternating white and black,
> starting with white.  
> the scheme for our little printer RLE is:
>
> -   runs of 0..251 inclusive are stored as a byte
>
> -   if larger, pull off chunks of 1536, 1152, 768, 384, 251 (encoded
>     as 255, 254, 253, 252, 251) until small enough
>
> when a large number is broken into chunks, each chunk needs to be
> suffixed by a zero so it snaps back to swap it back to the correct
> colour

In other words:

-   we are looking for a list of decimal numbers
-   each number is one byte long
-   each number encodes how many dots we should print in “current color”
-   colors alternate between white and black
-   the first number encodes white color

#### Mental exercise:

How would you encode “SOS” in Morse Code suing this scheme?

      Morse Code for SOS is: . . . - - - . . .  
      so, the "runs", starting from white would be:  
      0 1 1 1 1 1 1 2 1 2 1 2 1 1 1 1 1 1   
        .   .   .   -   -   -   .   .   .  

Well, probably the dashes should be longer and we would have to fill the
whole row of 384 pixels but I feel OK with the understanding of the
encoding.

Decoding image data
-------------------

The decoding process has a number of steps. Let’s make a procedure for
each of them.

If you want to see how everything fits together scroll to the [“LET’S
RUN THINGS”](#run-things) section towards the end of this file.

### Step 1: Read file contents into a string

Yes, I have captured a picture sent by a sirius server. You can catch
one to disk with “sirius-client” node app. You will find step-by-step
instructions on <https://tinyprinter.club/>

There is nothing special about this procedure. Just make sure that we
are not doing any text encoding conversions.

    proc readFileData {filename} {
      set fhandle [open $filename {RDONLY BINARY}]
      set data [read $fhandle]
      if ([catch {close $fhandle} err]) {
        puts "could't open $filename: $err"
      }
      return $data
    }

### Step 2: `base64` decode a string

I’m going to use a library procedure for that. No point in
re-implementing a wheel.

    source [file join tcllib base64.tcl]
    package require base64

Just run our data through the decoder:

    proc base64Decode {data} {
      return [base64::decode $data]
    }

### Step 3: Given a string of bytes, convert each byte to a decimal number

As far the the [“specification”](#spec) goes we are about to get the
list of “runs-lengths”.

    proc convertToDec {data} {
      binary scan $data cu* v 
      return $v
    }

### Step 4: Given a list of run-lenghts generate final “pixels”

First, a helper procedure:  
Remember how in the [“specification”](#spec) they say that numbers
greater than 251 encode longer runs? We will handle it now.

It seems like these longer runs are multiplies of 384 — the number of
pixels in one printed row.

    proc setRL {number} {
      if {$number == 252} {
        return 384
      } elseif {$number == 253} {
        return 768
      } elseif {$number == 254} {
        return 1152
      } elseif {$number == 255} {
        return 1536
      } else {
        return $number
      }
    }

#### Now, the heart of the image decoding.

We have a list of decimal numbers. We are going to generate one, long
stream of symbols — `0`s and `1`s — based on these decimals. The
algorithm is:

1.  take the decimal
2.  generate as many symbols as it encodes
3.  switch the symbol
4.  repeat until the end of the list

A `0` will encode a white pixel, a `1` a black one, so we start with
symbol `0`.

Just to be cleear, there is nothing in that stream that indicates rows.
It is just a long stream of symbols. When we display them (later) we
will just make a new row every 384 pixels.

Since this is the heart of the decoder, here’s some detailed explanation
how this particlaur code work.

The actual conversion is this command:

`string repeat $what $how-many-times`

Like the name suggests, `string repeat` repeats whatever string we give
it as many times as we tell it to.

In the actual decoding procedure you see:  
`string repeat $symbol [setRL $rl]`

-   in `$symbol` variable we have either `0` or `1`
-   in `$rl` we have run-length decimal coming from our image file
-   `[setRl $rl]` returns actual run-length
-   the command `string repeat` repeats that `$symbol` run-length-many
    times

The `[expr ($symbol + 1) % 2]` flips between `0` and `1`. It looks weird
but all it does is adding 1 to the previous `$symbol` value, divides by
2 and takes the reminder of that division. I know, an `if` statement
would be more clear conceptually here but it would make this simple
procedure much more clutered and we will need a similar trick once we
try to display pixels.

Anyway, `expr` simply calls math functions, so:  
`(0 + 1) % 2` yields 1  
`(1 + 1) % 2` yields 0

Finally, the “outer” `lmap` command just iterates over the list of
decimals the procedure received and assigns the current decimal to the
`$rl` variable.

At the end we `join` the list of generated runs to form one string from
them.

    proc convertDecToSymbols {decList} {
      # the spec says, start with `0` but we are flipping the symbol first
      # and only then emit the length of symbols, so we start from `1`
      set symbol 1
      set runs_list [ 
        lmap rl $decList { 
          set symbol [expr ($symbol + 1) % 2]
          string repeat $symbol [setRL $rl]
        }
      ]
      join $runs_list ""
    }

That’s it. We have decoded the image down to individual pixels. If I was
building a sirius client with this code I would now start encoding these
symbols into pixels in ESC/POS format. But since I’m not sure if it
worked I’d like to display what we got on the screen.

Displaying decoded images
-------------------------

First, we import the Tk graphics library:

    package require Tk

### Drawing canvas

We are going to use Tk canvas to display our pixels. So let’s create
one. Every time this procedure is called will (re)create an empty
canvas.

The global variable `scale` controls the size of a pixel on the screen.
More explanation [later](#run-things), when we set it.

    proc makeCanvas {height} {
      destroy .c
      canvas .c -width [expr 384 * $::scale] \
                -height [expr $height * $::scale] \
                -background grey80
      pack .c
    }

### Drawing one pixel

A helper procedure: draw a single pixel on a canvas

The 0,0 point of the canvas is in its top left corner. The global
variable `scale` controls the size of a pixel on the screen.

    proc drawPixel {x y {color black}} {
      set scaledX [expr $x * $::scale]
      set scaledY [expr $y * $::scale]
      .c create rectangle \
          $scaledX $scaledY \
          [expr $scaledX + $::scale] [expr $scaledY + $::scale] \
          -fill $color -outline $color
    }

### Drawing all our pixels

drawing all the symbols as pixels on a canvas

Given the string of `0`s and `1`s put pixels on a canvas in lines of 384
pixels. “0” will be white, “1” will be black.

Two, maybe not obvious things in this code:

One, since we don’t know how many symbols we are getting and if they
actually form proper lines—spoiler: they don’t, see
[Artefacts](#artefacts) below—we have to round up the height of the
canvas to make room for not complete lines.  
So, we’ll divide the number of symbols we got by 384 (as a `float`),
round it up and convert to an `integer`.

Two, how to easily calculate the coordinates of a pixel.  
We are drawing lines of 384 pixels and we start counting coordinates
from `0`. If we take the position of the pixel in the incoming stream
and divide it by the length of the line:

-   the integer part of the division will tell us the line number (so,
    the `y` coordinate)
-   the reminder will tell how far inside the line we are (so, the `x`
    coordinate)

E.g The pixel number `385` is in line 1 (counting from `0`) on position
1 (counting from `0`).

    proc drawPixelsOnCanvas {symbolStream} {
      set canvasHeight [expr int (ceil ([string length $symbolStream] / double (384)))]
      makeCanvas $canvasHeight
      set symbolCounter 0
      foreach symbol [split $symbolStream ""] {
        set x [expr $symbolCounter % 384]
        set y [expr $symbolCounter / 384]
        if {$symbol == 0} {set color "white"} else {set color "black"}
        drawPixel $x $y $color
        incr symbolCounter
      }
    }

<a name='artefacts'> Artefacts—stuff I don’t know </a>
------------------------------------------------------

When I decode a file sent over by the sirius server I get a number of
pixels (symbols) that is not divisible by 384, which is the width of a
printout.

There are also three visible artefacts when you just display this data
straight-up:

1.  The content is misaligned horizontally when compared to the original
    picture encoded by the sirius server.
2.  The last row of pixels is shorter than 384.
3.  There are a few lines with some random black pixels at the top of
    the image.

<img src="artefacts.png" style="width:100.0%" />  
See the `artefacts.png` for a full size image or open this one in a new
browser tab.

It seems like there is some data encoded in these bits before the actual
pixels start. If all you care are the pixels, let’s just cut away enough
bits from the begining of the stream.

It turns out that artefacts 1. and 2. can be fixed together if we
discard 245 symbols. BTW it is not divisible by 8 without a reminder so
at least part of this data is bit-based, not byte-based. Maybe some
specific instructions for the original thermal printer?

Once eveything is aligned and divisible by 384, let’s skip all the lines
that have these random pixels in them. After cutting 5 lines I ended up
with a clean image and exactly the same dimensions as the original I
copied from sirius server.

    proc cutOffsets {symbolStream} {
      # startOffset shifts the image horizontally
      set startOffset 245 
      # skipping lines with "random" black pixels
      set skipFirstLines 5
      set startIndex [expr $startOffset + (384 * $skipFirstLines)]
      set totalLength [string length $symbolStream]

      string range $symbolStream $startIndex $totalLength
    }

BONUS:
------

The next procedure can display decoded image in your terminal instead of
the graphical canvas. It is a bit clumsy to use because you have to
shrink your terminal text size so 384 characters will fit in one row. It
is much more convenient to use canvas for displaying pixels but if you
cannot use Tk graphics library this will work. Comment the line “package
require Tk” in the Tcl source file and you can run this code without Tk.

    proc printBitsInTerminal {symbols} {
      set startIndex 0
      set totalLength [string length $symbols]
      while {$startIndex <= $totalLength} {
        set endIndex [expr $startIndex + 383]
        puts [string range $symbols $startIndex $endIndex]
        set startIndex [expr $endIndex + 1]
      }
    }

Two helper procedures to get started in interactive mode
--------------------------------------------------------

Some handy info for people who would like to play with the code and a
convenient place to copy the drawing commands from:

    proc help {} {
      puts {---- help ----}
      puts "\nvariables set for you:\n \
       raw_data : \t\t\twhat was read from a file\n \
       decoded_raw_data : \t\tabove data base64 decoded\n \
       decimal_decoded_raw_data : \tabove data with each byte converted to a decimal number \n \
       symbolStream : \t\ta string of '0's and '1's decoded from decimal numbers above\n\n"
      puts {To draw:}
      puts {  drawPixelsOnCanvas $symbolStream}
      puts {To draw without artefacts:}
      puts {  drawPixelsOnCanvas [cutOffsets $symbolStream]}
      puts {}
      puts {--------}
    }

I expect some people may jump straight in and try to run the code as a
script. It will work in principle but they will not be able to interact
with the code, so let’s leave a note for them:

    proc noPrompt? {} {
      puts { No prompt?}
      puts {  Kill this with Control-c}
      puts {  and next time, don't give your Tcl interpreter this file as a parameter}
      puts {  but run the interpreter first and then:}
      puts {  source sirius-image-decoder.tcl}
      puts {}
      puts {Once you have prompt, type 'help' to see what you can do}
    }

<a name='run-things'>LET’S RUN THINGS</a>
-----------------------------------------

The global variable `scale` controls the size of a pixel on the canvas
because on my retina screen displaying pixel-for-pixel was too small to
examine the [artefacts](#artefacts). Scale 3 means each printer pixel
makes a 3x3 pixel square on the canvas.

    set scale 3

Now we’ll go through all the image decoding steps and keep all the
intermediate data to play with. We are now executing the decoding steps
be defined earlier.

Step 1: read imege data from the file:

    set raw_data [readFileData received_image.raw]

Step 2: take the raw data and base64 decode it:

    set decoded_raw_data [base64Decode $raw_data]

Step 3: convert decoded data to decimal numbers:

    set decimal_decoded_raw_data [convertToDec $decoded_raw_data]

Step 4: generate a long stream of ’0’s and ’1’s as these decimal numbers
define:

    set symbolStream [convertDecToSymbols $decimal_decoded_raw_data]

Finally, we print the info for people who run the code as a script
instead of sourcing it to an interactive session.

    noPrompt?

And that it :)

<a name=addendum>Addendum</a>
-----------------------------

### How is this documentation and code connected?

The document I wrote is `sirius-image-decoder.tmd` and it contains all
the text and all the code. In the `makefile` you can see how I generate
the file with code (sirius-image-decoder.tcl) and documentation in two
formats: markdown as README.md and an HTML version in `docs/` folder
which is served as a Github Page.

If you wanted to re-create everything you need `pandoc` to convert the
documentation to Github Markdown and HTML. The “tangling” of the source
and “weaving” of the documentation is done by the `lib/tmdoc.tcl` script
so no external dependencies here.
