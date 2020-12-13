#if SUPPORT_TAGGED_POINTERS
LNilOrTagged:
	// 如果是 nil，跳转 LReturnZero 处理
	b.eq	LReturnZero		// nil check

	// tagged
	// 获取 _objc_debug_taggedpointer_classes 表地址，放入 x10
	adrp	x10, _objc_debug_taggedpointer_classes@PAGE
	add	x10, x10, _objc_debug_taggedpointer_classes@PAGEOFF

	// 从 x0 中，提取 60 ~ 63 位，也就是 索引值，放入 x11
	ubfx	x11, x0, #60, #4

	// 从表中取出索引对应的项，也就是 class 地址，放入 x16。由于每项为 8 字节，所以左移 3 位
	ldr	x16, [x10, x11, LSL #3]

	// 获取 _OBJC_CLASS_$___NSUnrecognizedTaggedPointer 地址
	adrp	x10, _OBJC_CLASS_$___NSUnrecognizedTaggedPointer@PAGE
	add	x10, x10, _OBJC_CLASS_$___NSUnrecognizedTaggedPointer@PAGEOFF

	// 将取出的 class 地址与 NSUnrecognizedTaggedPointer 地址进行比较
	cmp	x10, x16

	// 不相等，则跳回主流程，进行缓存查找或者方法查找
	b.ne	LGetIsaDone

	// ext tagged
	// 如果相等，那么表示它是 extend tagged pointer，取出 _objc_debug_taggedpointer_ext_classes 地址放到 X10
	adrp	x10, _objc_debug_taggedpointer_ext_classes@PAGE
	add	x10, x10, _objc_debug_taggedpointer_ext_classes@PAGEOFF

	// 从 x0 中，提取 52 ~ 59 位，得到索引值
	ubfx	x11, x0, #52, #8

	// 获取 class 的地址
	ldr	x16, [x10, x11, LSL #3]

	// 跳回主流程
	b	LGetIsaDone
// SUPPORT_TAGGED_POINTERS


LReturnZero:
	// x0 is already zero
	// 将寄存器清 0
	mov	x1, #0
	movi	d0, #0
	movi	d1, #0
	movi	d2, #0
	movi	d3, #0
	ret
#endif