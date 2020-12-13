	ENTRY _objc_msgSend
	UNWIND _objc_msgSend, NoFrame

	// 将 self 和 0 进行比较
	cmp	p0, #0			// nil check and tagged pointer check
#if SUPPORT_TAGGED_POINTERS
	// <= 0，跳转到 LNilOrTagged，进行 nil 或者 tagged pointer 的处理。因为 tagged pointer 在 arm64 下，最高位为 1，作为有符号数 < 0
	b.le	LNilOrTagged		//  (MSB tagged pointer looks negative)
#else
	b.eq	LReturnZero
#endif
	
	// 将 isa 的值放到 x13
	ldr	p13, [x0]		// p13 = isa

	// 获取 class 的地址，放到 p16
	GetClassFromIsa_p16 p13		// p16 = class

LGetIsaDone:
	// calls imp or objc_msgSend_uncached
	// 在缓存中查找或进行完整方法查找
	CacheLookup NORMAL, _objc_msgSend

