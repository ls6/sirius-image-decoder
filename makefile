TCL-INTERP = ./tclkit-8.6.12 

code = sirius-image-decoder.tcl
docs = docs/index.html README.md

all: $(code) $(docs)

%.tcl: %.tmd
	@echo "\n### Making the tcl source file"
	$(TCL-INTERP) lib/tmdoc.tcl $< > $@ -mode tangle

docs: README.md docs/index.html

README.md: sirius-image-decoder.tmd
	@echo "\n### Making the README"
	$(TCL-INTERP) lib/tmdoc.tcl $< | pandoc --highlight-style pygments --to gfm -o $@

docs/index.html: sirius-image-decoder.tmd docs/dgw.css
	@echo "\n### Making the HTML documentation"
	$(TCL-INTERP) lib/tmdoc.tcl $< | pandoc --self-contained --highlight-style pygments --css=docs/dgw.css --to html -o $@