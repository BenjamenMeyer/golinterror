package main

import "fmt"

type headerVersionOne struct {
	value1 string
	value2 int
	value3 uint
}

type header headerVersionOne

func main() {
	h := &header{}
	h.value1 = "foo"
	h.value2 = -2593
	h.value3 = 29384

	fmt.Println("%#v", h)
}
