.macro GetClassFromIsa_p16 /* src */

// watchOS 上支持 SUPPORT_INDEXED_ISA，定义如下。

/*
#if __ARM_ARCH_7K__ >= 2  ||  (__arm64__ && !__LP64__)
#   define SUPPORT_INDEXED_ISA 1
#else
#   define SUPPORT_INDEXED_ISA 0
#endif
#
*/

#if SUPPORT_INDEXED_ISA
	// Indexed isa
	mov	p16, $0			// optimistically set dst = src

	// 条件分支，test be zero。 测试 p16 中 ISA_INDEX_IS_NPI_BIT 指定的位，若为 0，跳转到 label 1，无代码实现。也就表示 isa 是普通类的指针
	tbz	p16, #ISA_INDEX_IS_NPI_BIT, 1f	// done if not non-pointer isa
	// isa in p16 is indexed
	// 将 _objc_indexed_classes 表的地址放到 x10
	adrp	x10, _objc_indexed_classes@PAGE
	add	x10, x10, _objc_indexed_classes@PAGEOFF

	// ISA_INDEX_SHIFT = 2, ISA_INDEX_BIT = 15
	// 从 p16 中，从第 ISA_INDEX_SHIFT 位开始，提取 ISA_INDEX_BITS 个位放到 p16 中
	// 从第 2 位开始，提取 15 位，获取索引 indexCls 的值
	ubfx	p16, p16, #ISA_INDEX_SHIFT, #ISA_INDEX_BITS  // extract index

	// UXTP 表示无符号位段提取，PTRSHIFT = 3
	// 从 _objc_indexed_classes 表中获取索引对应的项，放到 p16 中
	ldr	p16, [x10, p16, UXTP #PTRSHIFT]	// load class from array
1:

#elif __LP64__
	// 64-bit packed isa
	// p16 & 0x0000000ffffffff8ULL，获取真正的类地址
	and	p16, $0, #ISA_MASK

#else
	// 32-bit raw isa
	mov	p16, $0

#endif

.endmacro