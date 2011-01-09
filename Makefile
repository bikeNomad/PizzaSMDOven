BINFILES=$(wildcard bin/*.rb)
LIBFILES=$(wildcard lib/*.rb)
RMODBUS_FILES=$(shell gem contents rmodbus)

tags: $(BINFILES) $(LIBFILES) $(RMODBUS_FILES)
	ctags -R $(BINFILES) $(LIBFILES) $(filter %.rb,$(RMODBUS_FILES))
