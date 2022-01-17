proc readFileData {filename} {
  set fhandle [open $filename {RDONLY BINARY}]
  set data [read $fhandle]
  if ([catch {close $fhandle} err]) {
    puts "could't open $filename: $err"
  }
  return $data
}
source [file join tcllib base64.tcl]
package require base64
proc base64Decode {data} {
  return [base64::decode $data]
}
proc convertToDec {data} {
  binary scan $data cu* v 
  return $v
}
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
package require Tk
proc makeCanvas {height} {
  destroy .c
  canvas .c -width [expr 384 * $::scale] \
            -height [expr $height * $::scale] \
            -background grey80
  pack .c
}
proc drawPixel {x y {color black}} {
  set scaledX [expr $x * $::scale]
  set scaledY [expr $y * $::scale]
  .c create rectangle \
      $scaledX $scaledY \
      [expr $scaledX + $::scale] [expr $scaledY + $::scale] \
      -fill $color -outline $color
}
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
proc cutOffsets {symbolStream} {
  # startOffset shifts the image horizontally
  set startOffset 245 
  # skipping lines with "random" black pixels
  set skipFirstLines 5
  set startIndex [expr $startOffset + (384 * $skipFirstLines)]
  set totalLength [string length $symbolStream]

  string range $symbolStream $startIndex $totalLength
}
proc printBitsInTerminal {symbols} {
  set startIndex 0
  set totalLength [string length $symbols]
  while {$startIndex <= $totalLength} {
    set endIndex [expr $startIndex + 383]
    puts [string range $symbols $startIndex $endIndex]
    set startIndex [expr $endIndex + 1]
  }
}
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
proc noPrompt? {} {
  puts { No prompt?}
  puts {  Kill this with Control-c}
  puts {  and next time, don't give your Tcl interpreter this file as a parameter}
  puts {  but run the interpreter first and then:}
  puts {  source sirius-image-decoder.tcl}
  puts {}
  puts {Once you have prompt, type 'help' to see what you can do}
}
set scale 3
set raw_data [readFileData received_image.raw]
set decoded_raw_data [base64Decode $raw_data]
set decimal_decoded_raw_data [convertToDec $decoded_raw_data]
set symbolStream [convertDecToSymbols $decimal_decoded_raw_data]
noPrompt?
