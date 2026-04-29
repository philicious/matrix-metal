APP=matrix-metal
SRC=MatrixMetal.mm

all:
	clang++ -std=c++17 -fobjc-arc -O2 $(SRC) -o $(APP) \
	  -framework Cocoa -framework Metal -framework MetalKit -framework QuartzCore

run: all
	./$(APP)

clean:
	rm -f $(APP)
