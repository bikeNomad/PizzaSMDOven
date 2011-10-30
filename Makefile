BINFILES:=$(wildcard bin/*.rb)
LIBFILES:=$(wildcard lib/*.rb)
RMODBUS_FILES:=$(filter %.rb,$(shell gem contents rmodbus))
SERIALPORT_FILES:=$(shell gem contents serialport)
SERIALPORT_C_FILES:=$(filter %.c,$(SERIALPORT_FILES))
SERIALPORT_RB_FILES:=$(filter %.rb,$(SERIALPORT_FILES))

run:
	bin/solder.rb

tags: $(BINFILES) $(LIBFILES) $(RMODBUS_FILES)
	/usr/local/bin/ctags --ruby-kinds=+cfmF --recurse=yes $(BINFILES) $(LIBFILES) $(RMODBUS_FILES)

clean:
	find logs -maxdepth 1 -empty -exec rm {} \;

docs:
	rdoc lib bin $(filter %.rb,$(RMODBUS_FILES)) $(SERIALPORT_C_FILES) $(SERIALPORT_RB_FILES)

test:
	@echo $(RMODBUS_FILES)
	@echo $(SERIALPORT_RB_FILES)
	@echo $(SERIALPORT_C_FILES)

.PHONY: clean run test
