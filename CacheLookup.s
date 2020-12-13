
// 缓存查找过程
.macro CacheLookup

LLookupStart$1:

	// p1 = SEL, p16 = isa
	// 将 cache_t 的地址放入 p11
	ldr	p11, [x16, #CACHE]				// p11 = mask|buckets

#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
	// 获取 buckets 地址
	and	p10, p11, #0x0000ffffffffffff	// p10 = buckets

	// 前 16 位是  mask，表示缓存表总共有多少项，x1 里面是 _cmd，根据 _cmd & mask 求出 _cmd 在表中对应的 index。
	and	p12, p1, p11, LSR #48		// x12 = _cmd & mask
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_LOW_4
	and	p10, p11, #~0xf			// p10 = buckets
	and	p11, p11, #0xf			// p11 = maskShift
	mov	p12, #0xffff
	lsr	p11, p12, p11				// p11 = mask = 0xffff >> p11
	and	p12, p1, p11				// x12 = _cmd & mask
#else
#error Unsupported cache mask storage for ARM64.
#endif

	
	// PTRSHIFT = 3，表中每一项大小为 16 字节，左移 4 位，相当于乘以 16。获取 index 对应项的地址，放到 x12。
	add	p12, p10, p12, LSL #(1+PTRSHIFT)
		             // p12 = buckets + ((_cmd & mask) << (1+PTRSHIFT))

    // 从定位到的表项地址中，取出 2 个 8 字节数据放到 p17, p9 中。其中 p17 里是 imp，p9 里是 sel。
	ldp	p17, p9, [x12]		// {imp, sel} = *bucket

	// 比较缓存中的 sel 和传入的 _cmd
1:	cmp	p9, p1			// if (bucket->sel != _cmd)

	// 不相等，跳转到 2
	b.ne	2f			//     scan more

	// 命中缓存，调用 imp
	CacheHit $0			// call or return imp
	
2:	// not hit: p12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0
	cmp	p12, p10		// wrap if bucket == buckets
	b.eq	3f
	ldp	p17, p9, [x12, #-BUCKET_SIZE]!	// {imp, sel} = *--bucket
	b	1b			// loop

3:	// wrap: p12 = first bucket, w11 = mask
#if CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_HIGH_16
	add	p12, p12, p11, LSR #(48 - (1+PTRSHIFT))
					// p12 = buckets + (mask << 1+PTRSHIFT)
#elif CACHE_MASK_STORAGE == CACHE_MASK_STORAGE_LOW_4
	add	p12, p12, p11, LSL #(1+PTRSHIFT)
					// p12 = buckets + (mask << 1+PTRSHIFT)
#else
#error Unsupported cache mask storage for ARM64.
#endif

	// Clone scanning loop to miss instead of hang when cache is corrupt.
	// The slow path may detect any corruption and halt later.

	ldp	p17, p9, [x12]		// {imp, sel} = *bucket
1:	cmp	p9, p1			// if (bucket->sel != _cmd)
	b.ne	2f			//     scan more
	CacheHit $0			// call or return imp
	
2:	// not hit: p12 = not-hit bucket
	CheckMiss $0			// miss if bucket->sel == 0

	// 比较取到的缓存项和缓存表地址是否一致，也就是是否是第一项
	cmp	p12, p10		// wrap if bucket == buckets

	// 相等，跳转到 3
	b.eq	3f

	// 从当前表项开始，继续往上找上一项
	ldp	p17, p9, [x12, #-BUCKET_SIZE]!	// {imp, sel} = *--bucket

	// 然后再次跳转到 1，进行循环比较
	b	1b			// loop

LLookupEnd$1:
LLookupRecover$1:
3:	// double wrap
	JumpMiss $0

.endmacro

// 命中缓存
.macro CacheHit
.if $0 == NORMAL
	// 调用 imp
	TailCallCachedImp x17, x12, x1, x16	// authenticate and call imp
.elseif $0 == GETIMP
	mov	p0, p17
	cbz	p0, 9f			// don't ptrauth a nil imp
	AuthAndResignAsIMP x0, x12, x1, x16	// authenticate imp and re-sign as IMP
9:	ret				// return IMP
.elseif $0 == LOOKUP
	// No nil check for ptrauth: the caller would crash anyway when they
	// jump to a nil IMP. We don't care if that jump also fails ptrauth.
	AuthAndResignAsIMP x17, x12, x1, x16	// authenticate imp and re-sign as IMP
	ret				// return imp via x17
.else
.abort oops
.endif
.endmacro


// 检查缓存项是否为空
.macro CheckMiss
	// miss if bucket->sel == 0
.if $0 == GETIMP
	cbz	p9, LGetImpMiss
.elseif $0 == NORMAL
	// 检查 p9 中的 sel 是否为空，若为空，则跳转到 __objc_msgSend_uncached，再进行缓存未命中的查找
	cbz	p9, __objc_msgSend_uncached
.elseif $0 == LOOKUP
	cbz	p9, __objc_msgLookup_uncached
.else
.abort oops
.endif
.endmacro

// 缓存未命中的处理
.macro JumpMiss
.if $0 == GETIMP
	b	LGetImpMiss
.elseif $0 == NORMAL
	// 调用 __objc_msgSend_uncached，进行缓存未命中的查找
	b	__objc_msgSend_uncached
.elseif $0 == LOOKUP
	b	__objc_msgLookup_uncached
.else
.abort oops
.endif
.endmacro

// 缓存未命中的查找
STATIC_ENTRY __objc_msgSend_uncached
	UNWIND __objc_msgSend_uncached, FrameWithNoSaves

	// THIS IS NOT A CALLABLE C FUNCTION
	// Out-of-band p16 is the class to search
	
	// 开始方法查找过程
	MethodTableLookup
	TailCallFunctionPointer x17

	END_ENTRY __objc_msgSend_uncached



// 方法查找
.macro MethodTableLookup

	// 保存寄存器
	SAVE_REGS

	// lookUpImpOrForward(obj, sel, cls, LOOKUP_INITIALIZE | LOOKUP_RESOLVER)
	// receiver and selector already in x0 and x1
	// 第 3 个参数是 cls，x16 中保存了 cls
	mov	x2, x16

	// LOOKUP_INITIALIZE = 1, LOOKUP_RESOLVER = 2, 两者或运算 = 3
	mov	x3, #3

	// 调用 _lookUpImpOrForward 进行查找，最后查找到的 imp 放到 x0 中
	bl	_lookUpImpOrForward

	// IMP in x0
	// 将 imp 放到 x17
	mov	x17, x0

	// 恢复寄存器
	RESTORE_REGS

.endmacro
