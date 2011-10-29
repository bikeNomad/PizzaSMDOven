BINFILES=$(wildcard bin/*.rb)
LIBFILES=$(wildcard lib/*.rb)
RMODBUS_FILES=$(shell gem contents rmodbus)
SERIALPORT_FILES=$(shell gem contents serialport)

run:
	bin/solder.rb

tags: $(BINFILES) $(LIBFILES) $(RMODBUS_FILES)
	/usr/local/bin/ctags --ruby-kinds=+cfmF --recurse=yes $(BINFILES) $(LIBFILES) $(filter %.rb,$(RMODBUS_FILES))

clean:
	find logs -maxdepth 1 -empty -exec rm {} \;

docs:
	rdoc lib bin $(filter %.rb,$(RMODBUS_FILES)) $(filter %.rb,$(SERIALPORT_FILES)) $(filter %.c,$(SERIALPORT_FILES))

.PHONY: clean run test
