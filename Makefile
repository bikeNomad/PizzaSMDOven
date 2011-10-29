BINFILES=$(wildcard bin/*.rb)
LIBFILES=$(wildcard lib/*.rb)
RMODBUS_FILES=$(shell gem contents rmodbus)
SERIALPORT_FILES=$(shell gem contents serialport)

run:
	bin/solder.rb

tags: $(BINFILES) $(LIBFILES) $(RMODBUS_FILES)
	/usr/local/bin/ctags --recurse=yes $(BINFILES) $(LIBFILES) $(filter %.rb,$(RMODBUS_FILES))

clean:
	find . -maxdepth 1 -empty -exec rm {} \;

test:
	echo $(PATH)
	echo $(SHELL)

docs:
	rdoc . $(filter %.rb,$(RMODBUS_FILES)) $(filter %.rb,$(SERIALPORT_FILES)) $(filter %.c,$(SERIALPORT_FILES))

.PHONY: clean run test
