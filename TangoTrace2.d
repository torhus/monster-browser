#line 2 "parts/Main.di"
module TangoTrace2;

private {
	import tango.core.Runtime;
	import tango.text.convert.Format;
}




void walkStack(LPCONTEXT ContextRecord, bool delegate(size_t) symIter) {
	size_t addr = ContextRecord.Eip;

	STACKFRAME64 frame;
	memset(&frame, 0, frame.sizeof);

	frame.AddrStack.Offset	= ContextRecord.Esp;
	frame.AddrPC.Offset		= ContextRecord.Eip;
	frame.AddrFrame.Offset	= ContextRecord.Ebp;
	frame.AddrStack.Mode	= frame.AddrPC.Mode = frame.AddrFrame.Mode = ADDRESS_MODE.AddrModeFlat;

	for (int sanity = 0; sanity < 256; ++sanity) {
		auto swres = StackWalk64(
			IMAGE_FILE_MACHINE_I386,
			GetCurrentProcess(),
			GetCurrentThread(),
			&frame,
			ContextRecord,
			null,
			SymFunctionTableAccess64,
			SymGetModuleBase64,
			null
		);
		
		if (!swres) {
			break;
		}

		if (!symIter(frame.AddrPC.Offset)) {
			break;
		}
	}
}


void addrToSymbolDetails(size_t addr, out char[] func, out char[] file, out int line) {
	ubyte buffer[1024];

	SYMBOL_INFO* symbol_info = cast(SYMBOL_INFO*)buffer.ptr;
	symbol_info.SizeOfStruct = SYMBOL_INFO.sizeof;
	symbol_info.MaxNameLen = buffer.length - SYMBOL_INFO.sizeof + 1;
	
	auto ln = getAddrDbgInfo(addr);

	char* symname = null;
	if (!SymFromAddr(GetCurrentProcess(), addr, null, symbol_info)) {
		//Stdout.formatln(SysError.lastMsg);
		symname = ln.func;
	} else {
		symname = symbol_info.Name.ptr;
	}

	func = fromStringz(symname).dup;
	file = fromStringz(ln.file).dup;
	line = ln.line;
}


class TangoTrace2Info : Exception.TraceInfo {
	int opApply(int delegate(ref char[]) dg) {
		char[] demangledFunc(char[] func) {
			if (func is null) {
				return "???";
			}
			if ("__Dmain" == func) {
				return "main";
			}
			scope demangler = new Demangler;
			try {
				func = demangler.demangle(func);
			} catch {}
			return func;
		}
		
		foreach (i, it; items) {
			char[] func, file;
			int line;
			addrToSymbolDetails(it, func, file, line);

			if (
					func != "_D11TangoTrace218tangoTrace2HandlerFPvZC9Exception9TraceInfo" &&
					func != "_D6object12traceContextFPvZC9Exception9TraceInfo"
			) {
				char[] str;
				if (0 == line) {
					str = Format("    at {}({})", demangledFunc(func), file is null ? "???" : file);
				} else {
					str = Format("    at {}({}:{})", demangledFunc(func), file is null ? "???" : file, line);
				}
				if (auto r = dg(str)) {
					return r;
				}
			}
			
			if ("__Dmain" == func) {
				break;
			}
		}
		return 0;
	}
	
	
	char[] toString() {
		char[] res;
		foreach (char[] c; this) {
			res ~= c;
			res ~= \n;
		}
		return res;
	}
	
	
	size_t[]	items;
}



Exception.TraceInfo tangoTrace2Handler(void* ptr) {
	uint eipReg, espReg, ebpReg;
	asm {
		call GIMMEH_EIP;
		GIMMEH_EIP:
			pop EAX;
			mov eipReg, EAX;
		mov espReg, ESP;
		mov ebpReg, EBP;
	}

	CONTEXT threadContext;
	threadContext.ContextFlags = CONTEXT_i386 | CONTEXT_CONTROL;
	GetThreadContext(GetCurrentThread(), &threadContext);
	
	threadContext.Eip = eipReg;
	threadContext.Esp = espReg;
	threadContext.Ebp = ebpReg;
	
	auto info = new TangoTrace2Info;

	walkStack(&threadContext, (size_t addr) {
		info.items ~= addr;
		return true;
	});
	return info;
}
#line 2 "parts/Memory.di"
private {
	import tango.stdc.stdlib : cMalloc = malloc, cRealloc = realloc, cFree = free;
}

public {
	import tango.stdc.string : memset;
}


/**
	Allocate the array using malloc
	
	Params:
	array = the array which will be resized
	numItems = number of items to be allocated in the array
	init = whether to init the allocated items to their default values or not
	
	Examples:
	int[] foo;
	foo.alloc(20);
	
	Remarks:
	The array must be null and empty for this function to succeed. The rationale behind this is that the coder should state his decision clearly. This will help and has
	already helped to spot many intricate bugs. 
*/
void alloc(T, intT)(inout T array, intT numItems, bool init = true) 
in {
	assert (array is null);
	assert (numItems >= 0);
}
out {
	assert (numItems == array.length);
}
body {
	alias typeof(T[0]) ItemT;
	array = (cast(ItemT*)cMalloc(ItemT.sizeof * numItems))[0 .. numItems];
	
	static if (is(typeof(ItemT.init))) {
		if (init) {
			array[] = ItemT.init;
		}
	}
}


/**
	Clone the given array. The result is allocated using alloc() and copied piecewise from the param. Then it's returned
*/
T clone(T)(T array) {
	T res;
	res.alloc(array.length, false);
	res[] = array[];
	return res;
}


/**
	Realloc the contents of an array
	
	array = the array which will be resized
	numItems = the new size for the array
	init = whether to init the newly allocated items to their default values or not
	
	Examples:
	int[] foo;
	foo.alloc(20);
	foo.realloc(10);		// <--
*/
void realloc(T, intT)(inout T array, intT numItems, bool init = true)
in {
	assert (numItems >= 0);
}
out {
	assert (numItems == array.length);
}
body {
	alias typeof(T[0]) ItemT;
	intT oldLen = array.length;
	array = (cast(ItemT*)cRealloc(array.ptr, ItemT.sizeof * numItems))[0 .. numItems];
	
	static if (is(typeof(ItemT.init))) {
		if (init && numItems > oldLen) {
			array[oldLen .. numItems] = ItemT.init;
		}
	}
}


/**
	Deallocate an array allocated with alloc()
*/
void free(T)(inout T array)
out {
	assert (0 == array.length);
}
body {
	cFree(array.ptr);
	array = null;
}


/**
	Append an item to an array. Optionally keep track of an external 'real length', while doing squared reallocation of the array
	
	Params:
	array = the array to append the item to
	elem = the new item to be appended
	realLength = the optional external 'real length'
	
	Remarks:
	if realLength isn't null, the array is not resized by one, but allocated in a std::vector manner. The array's length becomes it's capacity, while 'realLength'
	is the number of items in the array.
	
	Examples:
	---
	uint barLen = 0;
	int[] bar;
	append(bar, 10, &barLen);
	append(bar, 20, &barLen);
	append(bar, 30, &barLen);
	append(bar, 40, &barLen);
	assert (bar.length == 16);
	assert (barLen == 4);
	---
*/
void append(T, I)(inout T array, I elem, uint* realLength = null) {
	uint len = realLength is null ? array.length : *realLength;
	uint capacity = array.length;
	alias typeof(T[0]) ItemT;
	
	if (len >= capacity) {
		if (realLength is null) {		// just add one element to the array
			int numItems = len+1;
			array = (cast(ItemT*)cRealloc(array.ptr, ItemT.sizeof * numItems))[0 .. numItems];
		} else {								// be smarter and allocate in power-of-two increments
			const uint initialCapacity = 4;
			int numItems = capacity == 0 ? initialCapacity : capacity * 2; 
			array = (cast(ItemT*)cRealloc(array.ptr, ItemT.sizeof * numItems))[0 .. numItems];
			++*realLength;
		}
	} else if (realLength !is null) ++*realLength;
	
	array[len] = elem;
}
#line 2 "parts/WinApi.di"
import tango.text.Util;
import tango.io.Stdout;
import tango.core.Thread;
import tango.core.Array;
import tango.sys.Common : SysError;
import tango.sys.SharedLib : SharedLib;
import tango.stdc.stdio;
import tango.stdc.string;
import tango.stdc.stringz;





enum {
	MAX_PATH = 260,
}

enum : WORD {
	IMAGE_FILE_MACHINE_UNKNOWN = 0,
	IMAGE_FILE_MACHINE_I386    = 332,
	IMAGE_FILE_MACHINE_R3000   = 354,
	IMAGE_FILE_MACHINE_R4000   = 358,
	IMAGE_FILE_MACHINE_R10000  = 360,
	IMAGE_FILE_MACHINE_ALPHA   = 388,
	IMAGE_FILE_MACHINE_POWERPC = 496
}

version(X86) {
	const SIZE_OF_80387_REGISTERS=80;
	const CONTEXT_i386=0x10000;
	const CONTEXT_i486=0x10000;
	const CONTEXT_CONTROL=(CONTEXT_i386|0x00000001L);
	const CONTEXT_INTEGER=(CONTEXT_i386|0x00000002L);
	const CONTEXT_SEGMENTS=(CONTEXT_i386|0x00000004L);
	const CONTEXT_FLOATING_POINT=(CONTEXT_i386|0x00000008L);
	const CONTEXT_DEBUG_REGISTERS=(CONTEXT_i386|0x00000010L);
	const CONTEXT_EXTENDED_REGISTERS=(CONTEXT_i386|0x00000020L);
	const CONTEXT_FULL=(CONTEXT_CONTROL|CONTEXT_INTEGER|CONTEXT_SEGMENTS);
	const MAXIMUM_SUPPORTED_EXTENSION=512;

	struct FLOATING_SAVE_AREA {
		DWORD    ControlWord;
		DWORD    StatusWord;
		DWORD    TagWord;
		DWORD    ErrorOffset;
		DWORD    ErrorSelector;
		DWORD    DataOffset;
		DWORD    DataSelector;
		BYTE[80] RegisterArea;
		DWORD    Cr0NpxState;
	}

	struct CONTEXT {
		DWORD ContextFlags;
		DWORD Dr0;
		DWORD Dr1;
		DWORD Dr2;
		DWORD Dr3;
		DWORD Dr6;
		DWORD Dr7;
		FLOATING_SAVE_AREA FloatSave;
		DWORD SegGs;
		DWORD SegFs;
		DWORD SegEs;
		DWORD SegDs;
		DWORD Edi;
		DWORD Esi;
		DWORD Ebx;
		DWORD Edx;
		DWORD Ecx;
		DWORD Eax;
		DWORD Ebp;
		DWORD Eip;
		DWORD SegCs;
		DWORD EFlags;
		DWORD Esp;
		DWORD SegSs;
		BYTE[MAXIMUM_SUPPORTED_EXTENSION] ExtendedRegisters;
	}

} else {
	pragma(msg, "Unsupported CPU");
	static assert(0);
	// Versions for PowerPC, Alpha, SHX, and MIPS removed.
}


alias CONTEXT* PCONTEXT, LPCONTEXT;


ushort MAKEWORD(ubyte a, ubyte b) {
	return cast(ushort) ((b << 8) | a);
}

uint MAKELONG(ushort a, ushort b) {
	return cast(uint) ((b << 16) | a);
}

ushort LOWORD(uint l) {
	return cast(ushort) l;
}

ushort HIWORD(uint l) {
	return cast(ushort) (l >>> 16);
}

ubyte LOBYTE(ushort w) {
	return cast(ubyte) w;
}

ubyte HIBYTE(ushort w) {
	return cast(ubyte) (w >>> 8);
}

template max(T) {
	T max(T a, T b) {
		return a > b ? a : b;
	}
}

template min(T) {
	T min(T a, T b) {
		return a < b ? a : b;
	}
}

typedef void* HANDLE;


alias void VOID;
alias char CHAR;
alias short SHORT;
alias char CCHAR;
alias CCHAR* PCCHAR;
alias ubyte UCHAR;
alias UCHAR* PUCHAR;
alias char* PSZ;
alias void* PVOID, LPVOID;

/* FIXME(MinGW) for __WIN64 */
alias void* PVOID64;

alias wchar WCHAR;
alias WCHAR* PWCHAR, LPWCH, PWCH, LPWSTR, PWSTR;
alias CHAR* PCHAR, LPCH, PCH, LPSTR, PSTR;

// const versions
alias WCHAR* LPCWCH, PCWCH, LPCWSTR, PCWSTR;
alias CHAR* LPCCH, PCSTR, LPCSTR;

version(Unicode) {
	alias WCHAR TCHAR, _TCHAR;
} else {
	alias CHAR TCHAR, _TCHAR;
}

alias TCHAR TBYTE;
alias TCHAR* PTCH, PTBYTE, LPTCH, PTSTR, LPTSTR, LP, PTCHAR, LPCTSTR;

alias SHORT* PSHORT;
alias LONG* PLONG;


alias HANDLE* PHANDLE, LPHANDLE;
alias DWORD LCID;
alias PDWORD PLCID;
alias WORD LANGID;

alias long LONGLONG;
alias ulong DWORDLONG;

alias DWORDLONG ULONGLONG;
alias LONGLONG* PLONGLONG;
alias DWORDLONG* PDWORDLONG, PULONGLONG;
alias LONGLONG USN;

const char ANSI_NULL = '\0';
const wchar UNICODE_NULL = '\0';
alias bool BOOLEAN;
alias bool* PBOOLEAN;

alias BYTE FCHAR;
alias WORD FSHORT;
alias DWORD FLONG;

alias ubyte   BYTE;
alias ubyte*  PBYTE, LPBYTE;
alias ushort  USHORT, WORD, ATOM;
alias ushort* PUSHORT, PWORD, LPWORD;
alias uint    ULONG, DWORD, UINT, COLORREF;
alias uint*   PULONG, PDWORD, LPDWORD, PUINT, LPUINT;
alias int     WINBOOL, BOOL, INT, LONG, HFILE;
alias int*    PWINBOOL, LPWINBOOL, PBOOL, LPBOOL, PINT, LPINT, LPLONG;
alias float   FLOAT;
alias float*  PFLOAT;
alias void*   PCVOID, LPCVOID;

alias UINT_PTR WPARAM;
alias LONG_PTR LPARAM, LRESULT;

alias LONG HRESULT;

alias HANDLE HGLOBAL, HLOCAL, GLOBALHANDLE, LOCALHANDLE, HGDIOBJ, HACCEL,
  HBITMAP, HBRUSH, HCOLORSPACE, HDC, HGLRC, HDESK, HENHMETAFILE, HFONT,
  HICON, HKEY, HMENU, HMETAFILE, HINSTANCE, HMODULE, HPALETTE, HPEN, HRGN,
  HRSRC, HSTR, HTASK, HWND, HWINSTA, HKL, HCURSOR;
alias HANDLE* PHKEY;

alias extern (Windows) int function() FARPROC, NEARPROC, PROC;

struct RECT {
	LONG left;
	LONG top;
	LONG right;
	LONG bottom;
}
alias RECT RECTL;
alias RECT* PRECT, LPRECT, LPCRECT, PRECTL, LPRECTL, LPCRECTL;

struct POINT {
	LONG x;
	LONG y;
}
alias POINT POINTL;
alias POINT* PPOINT, LPPOINT, PPOINTL, LPPOINTL;

struct SIZE {
	LONG cx;
	LONG cy;
}
alias SIZE SIZEL;
alias SIZE* PSIZE, LPSIZE, PSIZEL, LPSIZEL;

struct POINTS {
	SHORT x;
	SHORT y;
}
alias POINTS* PPOINTS, LPPOINTS;

enum : BOOL {
	FALSE = 0,
	TRUE = 1,
}



// basetsd

version (Win64) {
	alias long __int3264;
	enum : ulong { ADDRESS_TAG_BIT = 0x40000000000 }

	alias long INT_PTR, LONG_PTR;
	alias long* PINT_PTR, PLONG_PTR;
	alias ulong UINT_PTR, ULONG_PTR, HANDLE_PTR;
	alias ulong* PUINT_PTR, PULONG_PTR;
	alias int HALF_PTR;
	alias int* PHALF_PTR;
	alias uint UHALF_PTR;
	alias uint* PUHALF_PTR;
	// LATER: translate *To* functions once Win64 is here
} else {
	alias int __int3264;
	enum : uint { ADDRESS_TAG_BIT = 0x80000000 }

	alias int INT_PTR, LONG_PTR;
	alias int* PINT_PTR, PLONG_PTR;
	alias uint UINT_PTR, ULONG_PTR, HANDLE_PTR;
	alias uint* PUINT_PTR, PULONG_PTR;
	alias short HALF_PTR;
	alias short* PHALF_PTR;
	alias ushort UHALF_PTR;
	alias ushort* PUHALF_PTR;

	uint HandleToUlong(HANDLE h)    { return cast(uint) h; }
	int HandleToLong(HANDLE h)      { return cast(int) h; }
	HANDLE LongToHandle(LONG_PTR h) { return cast(HANDLE) h; }
	uint PtrToUlong(void* p)        { return cast(uint) p; }
	uint PtrToUint(void* p)         { return cast(uint) p; }
	int PtrToInt(void* p)           { return cast(int) p; }
	ushort PtrToUshort(void* p)     { return cast(ushort) p; }
	short PtrToShort(void* p)       { return cast(short) p; }
	void* IntToPtr(int i)           { return cast(void*) i; }
	void* UIntToPtr(uint ui)        { return cast(void*) ui; }
	alias IntToPtr LongToPtr;
	alias UIntToPtr ULongToPtr;
}

alias UIntToPtr UintToPtr, UlongToPtr;

enum : UINT_PTR {
	MAXUINT_PTR = UINT_PTR.max
}

enum : INT_PTR {
	MAXINT_PTR = INT_PTR.max,
	MININT_PTR = INT_PTR.min
}

enum : ULONG_PTR {
	MAXULONG_PTR = ULONG_PTR.max
}

enum : LONG_PTR {
	MAXLONG_PTR = LONG_PTR.max,
	MINLONG_PTR = LONG_PTR.min
}

enum : UHALF_PTR {
	MAXUHALF_PTR = UHALF_PTR.max
}

enum : HALF_PTR {
	MAXHALF_PTR = HALF_PTR.max,
	MINHALF_PTR = HALF_PTR.min
}

alias int LONG32, INT32;
alias int* PLONG32, PINT32;
alias uint ULONG32, DWORD32, UINT32;
alias uint* PULONG32, PDWORD32, PUINT32;

alias ULONG_PTR SIZE_T, DWORD_PTR;
alias ULONG_PTR* PSIZE_T, PDWORD_PTR;
alias LONG_PTR SSIZE_T;
alias LONG_PTR* PSSIZE_T;

alias long LONG64, INT64;
alias long* PLONG64, PINT64;
alias ulong ULONG64, DWORD64, UINT64;
alias ulong* PULONG64, PDWORD64, PUINT64;


extern(Windows) {
	HANDLE GetCurrentProcess();
	HANDLE GetCurrentThread();
	BOOL GetThreadContext(HANDLE, LPCONTEXT);
}


void loadWinAPIFunctions() {
	auto dbghelp = SharedLib.load(`dbghelp.dll`);
	
	auto SymEnumerateModules64 = cast(fp_SymEnumerateModules64)dbghelp.getSymbol("SymEnumerateModules64");
	SymFromAddr = cast(fp_SymFromAddr)dbghelp.getSymbol("SymFromAddr");
	assert (SymFromAddr !is null);
	SymLoadModule64 = cast(fp_SymLoadModule64)dbghelp.getSymbol("SymLoadModule64");
	assert (SymLoadModule64 !is null);
	SymInitialize = cast(fp_SymInitialize)dbghelp.getSymbol("SymInitialize");
	assert (SymInitialize !is null);
	SymCleanup = cast(fp_SymCleanup)dbghelp.getSymbol("SymCleanup");
	assert (SymCleanup !is null);
	SymSetOptions = cast(fp_SymSetOptions)dbghelp.getSymbol("SymSetOptions");
	assert (SymSetOptions !is null);
	SymGetLineFromAddr64 = cast(fp_SymGetLineFromAddr64)dbghelp.getSymbol("SymGetLineFromAddr64");
	assert (SymGetLineFromAddr64 !is null);
	SymEnumSymbols = cast(fp_SymEnumSymbols)dbghelp.getSymbol("SymEnumSymbols");
	assert (SymEnumSymbols !is null);
	SymGetModuleBase64 = cast(fp_SymGetModuleBase64)dbghelp.getSymbol("SymGetModuleBase64");
	assert (SymGetModuleBase64 !is null);
	StackWalk64 = cast(fp_StackWalk64)dbghelp.getSymbol("StackWalk64");
	assert (StackWalk64 !is null);
	SymFunctionTableAccess64 = cast(fp_SymFunctionTableAccess64)dbghelp.getSymbol("SymFunctionTableAccess64");
	assert (SymFunctionTableAccess64 !is null);
	
	
	auto psapi = SharedLib.load(`psapi.dll`);
	GetModuleFileNameExA = cast(fp_GetModuleFileNameExA)psapi.getSymbol("GetModuleFileNameExA");
	assert (GetModuleFileNameExA !is null);
}



extern (Windows) {
	fp_SymFromAddr		SymFromAddr;
	fp_SymLoadModule64	SymLoadModule64;
	fp_SymInitialize			SymInitialize;
	fp_SymCleanup			SymCleanup;
	fp_SymSetOptions		SymSetOptions;
	fp_SymGetLineFromAddr64	SymGetLineFromAddr64;
	fp_SymEnumSymbols			SymEnumSymbols;
	fp_SymGetModuleBase64	SymGetModuleBase64;
	fp_GetModuleFileNameExA		GetModuleFileNameExA;
	fp_StackWalk64						StackWalk64;
	fp_SymFunctionTableAccess64	SymFunctionTableAccess64;


	alias DWORD function(
		DWORD SymOptions
	) fp_SymSetOptions;
	
	enum {
		SYMOPT_ALLOW_ABSOLUTE_SYMBOLS = 0x00000800,
		SYMOPT_DEFERRED_LOADS = 0x00000004,
		SYMOPT_UNDNAME = 0x00000002
	}

	alias BOOL function(
		HANDLE hProcess,
		LPCTSTR UserSearchPath,
		BOOL fInvadeProcess
	) fp_SymInitialize;
	
	alias BOOL function(
		HANDLE hProcess
	) fp_SymCleanup;

	alias DWORD64 function(
		HANDLE hProcess,
		HANDLE hFile,
		LPSTR ImageName,
		LPSTR ModuleName,
		DWORD64 BaseOfDll,
		DWORD SizeOfDll
	) fp_SymLoadModule64;
	
	struct SYMBOL_INFO {
		ULONG SizeOfStruct;
		ULONG TypeIndex;
		ULONG64 Reserved[2];
		ULONG Index;
		ULONG Size;
		ULONG64 ModBase;
		ULONG Flags;
		ULONG64 Value;
		ULONG64 Address;
		ULONG Register;
		ULONG Scope;
		ULONG Tag;
		ULONG NameLen;
		ULONG MaxNameLen;
		TCHAR Name[1];
	}
	alias SYMBOL_INFO* PSYMBOL_INFO;
	
	alias BOOL function(
		HANDLE hProcess,
		DWORD64 Address,
		PDWORD64 Displacement,
		PSYMBOL_INFO Symbol
	) fp_SymFromAddr;

	alias BOOL function(
		HANDLE hProcess,
		PSYM_ENUMMODULES_CALLBACK64 EnumModulesCallback,
		PVOID UserContext
	) fp_SymEnumerateModules64;
	
	alias BOOL function(
		LPTSTR ModuleName,
		DWORD64 BaseOfDll,
		PVOID UserContext
	) PSYM_ENUMMODULES_CALLBACK64;

	const DWORD TH32CS_SNAPPROCESS = 0x00000002;
	const DWORD TH32CS_SNAPTHREAD = 0x00000004;
	
	HANDLE CreateToolhelp32Snapshot(
		DWORD dwFlags,
		DWORD th32ProcessID
	);

	BOOL Process32First(
		HANDLE hSnapshot,
		LPPROCESSENTRY32 lppe
	);
	
	BOOL Process32Next(
		HANDLE hSnapshot,
		LPPROCESSENTRY32 lppe
	);
	
	BOOL Thread32First(
		HANDLE hSnapshot,
		LPTHREADENTRY32 lpte
	);

	BOOL Thread32Next(
		HANDLE hSnapshot,
		LPTHREADENTRY32 lpte
	);

	struct PROCESSENTRY32 {
		DWORD dwSize;
		DWORD cntUsage;
		DWORD th32ProcessID;
		ULONG_PTR th32DefaultHeapID;
		DWORD th32ModuleID;
		DWORD cntThreads;
		DWORD th32ParentProcessID;
		LONG pcPriClassBase;
		DWORD dwFlags;
		TCHAR szExeFile[MAX_PATH];
	}
	alias PROCESSENTRY32* LPPROCESSENTRY32;
	
	struct THREADENTRY32 {
		DWORD dwSize;
		DWORD cntUsage;
		DWORD th32ThreadID;
		DWORD th32OwnerProcessID;
		LONG tpBasePri;
		LONG tpDeltaPri;
		DWORD dwFlags;
	}
	alias THREADENTRY32* LPTHREADENTRY32;


	enum {
		MAX_MODULE_NAME32 = 255,
		TH32CS_SNAPMODULE = 0x00000008,
		SYMOPT_LOAD_LINES = 0x10,
	}

   struct MODULEENTRY32 {
		DWORD  dwSize;
		DWORD  th32ModuleID;
		DWORD  th32ProcessID;
		DWORD  GlblcntUsage;
		DWORD  ProccntUsage;
		BYTE  *modBaseAddr;
		DWORD  modBaseSize;
		HMODULE hModule;
		char   szModule[MAX_MODULE_NAME32 + 1];
		char   szExePath[MAX_PATH];
	}

	struct IMAGEHLP_LINE64 {
		DWORD SizeOfStruct;
		PVOID Key;
		DWORD LineNumber;
		PTSTR FileName;
		DWORD64 Address;
	}
	alias IMAGEHLP_LINE64* PIMAGEHLP_LINE64;
 

	BOOL Module32First(HANDLE, MODULEENTRY32*);
	BOOL Module32Next(HANDLE, MODULEENTRY32*);


	alias BOOL function(
		HANDLE hProcess,
		DWORD64 dwAddr,
		PDWORD pdwDisplacement,
		PIMAGEHLP_LINE64 Line
	) fp_SymGetLineFromAddr64;


	
	alias BOOL function(
		PSYMBOL_INFO pSymInfo,
		ULONG SymbolSize,
		PVOID UserContext
	) PSYM_ENUMERATESYMBOLS_CALLBACK;

	alias BOOL function(
		HANDLE hProcess,
		ULONG64 BaseOfDll,
		LPCTSTR Mask,
		PSYM_ENUMERATESYMBOLS_CALLBACK EnumSymbolsCallback,
		PVOID UserContext
	) fp_SymEnumSymbols;


	alias DWORD64 function(
		HANDLE hProcess,
		DWORD64 dwAddr
	) fp_SymGetModuleBase64;
	alias fp_SymGetModuleBase64 PGET_MODULE_BASE_ROUTINE64;
	
	
	alias DWORD function(
	  HANDLE hProcess,
	  HMODULE hModule,
	  LPSTR lpFilename,
	  DWORD nSize
	) fp_GetModuleFileNameExA;
	

	enum ADDRESS_MODE {
		AddrMode1616,
		AddrMode1632,
		AddrModeReal,
		AddrModeFlat
	}
	
	struct KDHELP64 {
		DWORD64 Thread;
		DWORD ThCallbackStack;
		DWORD ThCallbackBStore;
		DWORD NextCallback;
		DWORD FramePointer;
		DWORD64 KiCallUserMode;
		DWORD64 KeUserCallbackDispatcher;
		DWORD64 SystemRangeStart;
		DWORD64 KiUserExceptionDispatcher;
		DWORD64 StackBase;
		DWORD64 StackLimit;
		DWORD64 Reserved[5];
	} 
	alias KDHELP64* PKDHELP64;
	
	struct ADDRESS64 {
		DWORD64 Offset;
		WORD Segment;
		ADDRESS_MODE Mode;
	}
	alias ADDRESS64* LPADDRESS64;


	struct STACKFRAME64 {
		ADDRESS64 AddrPC;
		ADDRESS64 AddrReturn;
		ADDRESS64 AddrFrame;
		ADDRESS64 AddrStack;
		ADDRESS64 AddrBStore;
		PVOID FuncTableEntry;
		DWORD64 Params[4];
		BOOL Far;
		BOOL Virtual;
		DWORD64 Reserved[3];
		KDHELP64 KdHelp;
	}
	alias STACKFRAME64* LPSTACKFRAME64;
	
	
	
	alias BOOL function(
		HANDLE hProcess,
		DWORD64 lpBaseAddress,
		PVOID lpBuffer,
		DWORD nSize,
		LPDWORD lpNumberOfBytesRead
	) PREAD_PROCESS_MEMORY_ROUTINE64;
	
	alias PVOID function(
		HANDLE hProcess,
		DWORD64 AddrBase
	) PFUNCTION_TABLE_ACCESS_ROUTINE64;
	alias PFUNCTION_TABLE_ACCESS_ROUTINE64 fp_SymFunctionTableAccess64;
	
	alias DWORD64 function(
		HANDLE hProcess,
		HANDLE hThread,
		LPADDRESS64 lpaddr
	) PTRANSLATE_ADDRESS_ROUTINE64;
	
	
	alias BOOL function (
		DWORD MachineType,
		HANDLE hProcess,
		HANDLE hThread,
		LPSTACKFRAME64 StackFrame,
		PVOID ContextRecord,
		PREAD_PROCESS_MEMORY_ROUTINE64 ReadMemoryRoutine,
		PFUNCTION_TABLE_ACCESS_ROUTINE64 FunctionTableAccessRoutine,
		PGET_MODULE_BASE_ROUTINE64 GetModuleBaseRoutine,
		PTRANSLATE_ADDRESS_ROUTINE64 TranslateAddress
	) fp_StackWalk64;	
}
#line 2 "parts/Demangler.di"
/**
	D symbol name demangling

	Attempts to demangle D symbols generated by the DMD frontend.
	(Which is not always technically possible)

   Copyright: Copyright (C) 2007-2008 Zygfryd (aka Hxal). All rights reserved.
   License:   zlib
   Authors:   Zygfryd (aka Hxal)

 */


private import tango.stdc.stdlib : alloca;
private import tango.text.Unicode : isLetter, isLetterOrDigit;
private import tango.util.Convert : to;
private import tango.text.Util : locatePattern;

//import tango.io.Stdout;

/**
   
 */
public class Demangler
{
	debug(traceDemangler) private char[][] _trace;

	/** How deeply to recurse printing template parameters,
	  * for depths greater than this, an ellipsis is used */
	uint templateExpansionDepth = 1;

	/** Skip default members of templates (sole members named after
	  * the template) */
	bool foldDefaults = true;

	/** Print types of functions being part of the main symbol */
	bool expandFunctionTypes = false;

	/** For composite types, print the kind (class|struct|etc.) of the type */
	bool printTypeKind = false;

	/** */
	public void verbosity (uint level)
	{
		switch (level)
		{
			case 0:
				templateExpansionDepth = 0;
				expandFunctionTypes = false;
				printTypeKind = false;
				break;

			case 1:
				templateExpansionDepth = 1;
				expandFunctionTypes = false;
				printTypeKind = false;
				break;

			case 2:
				templateExpansionDepth = 1;
				expandFunctionTypes = false;
				printTypeKind = true;
				break;

			case 3:
				templateExpansionDepth = 1;
				expandFunctionTypes = true;
				printTypeKind = true;
				break;

			default:
				templateExpansionDepth = level - 2;
				expandFunctionTypes = true;
				printTypeKind = true;
		}
	}

	/** */
	this ()
	{
		verbosity (1);
	}

	/** */
	this (uint verbosityLevel)
	{
		verbosity (verbosityLevel);
	}

	private char[] input;
	private uint _templateDepth = 0;

	debug (traceDemangler)
	{
		private void trace (char[] where)
		{
			if (_trace.length > 500)
				throw new Exception ("Infinite recursion");

			char[] spaces = (cast(char*) alloca (_trace.length)) [0 .. _trace.length];
			spaces[] = ' ';
			if (input.length < 50)
				Stdout.formatln ("{}{} : {{{}}", spaces, where, input);
			else
				Stdout.formatln ("{}{} : {{{}}", spaces, where, input[0..50]);
			_trace ~= where;
		}

		private void report (T...) (char[] fmt, T args)
		{
			char[] spaces = (cast(char*) alloca (_trace.length)) [0 .. _trace.length];
			spaces[] = ' ';
			Stdout (spaces);
			Stdout.formatln (fmt, args);
		}

		private void trace (bool result)
		{
			//auto tmp = _trace[$-1];
			_trace = _trace[0..$-1];
				char[] spaces = (cast(char*) alloca (_trace.length)) [0 .. _trace.length];
				spaces[] = ' ';
				Stdout(spaces);
			if (!result)
				Stdout.formatln ("fail");
			else
				Stdout.formatln ("success");
		}
	}

	private char[] consume (uint amt)
	{
		char[] tmp = input[0 .. amt];
		input = input[amt .. $];
		return tmp;
	}

	/** */
	public char[] demangle (char[] input)
	{
		this.input = input;
		Buffer buf;
		if (MangledName (buf))
			return buf.slice.dup;
		else
			return input;
	}

	/** */
	public char[] demangle (char[] input, char[] output)
	{
		this.input = input;
		Buffer buf;
		if (MangledName (buf))
		{
			output[] = buf.slice;
			return output;
		}
		else
			return input;
	}

	private:

	bool MangledName (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("MangledName");

		if (input[0..2] != "_D")
			return false;

		consume (2);

		if (! TypedQualifiedName (output))
			return false;

// 		if (input.length > 0 && input[0] == 'M')
// 		{
// 			consume (1);
// 
// 			Buffer typebuf;
// 
// 			if (! Type (typebuf))
// 				return false;
// 		}

		//Stdout.formatln ("MangledName={}", namebuf.slice);

		return true;
	}

	bool TypedQualifiedName (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TypedQualifiedName");

		Buffer car;
		if (! SymbolName (car))
			return false;
		output.append (car);

		Buffer type; // undocumented
		if (TypeFunction (type) && expandFunctionTypes)
		{
			output.append ("{");
			output.append (type);
			output.append ("}");
		}

		Buffer cdr;
		if (TypedQualifiedName (cdr))
		{
			if (!foldDefaults || !locatePattern (car.slice, cdr.slice) == 0)
			{
				output.append (".");
				output.append (cdr);
			}
		}

		return true;
	}

	bool QualifiedName (ref Buffer output, bool aliasHack = false)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace (aliasHack ? "QualifiedNameAH" : "QualifiedName");

		Buffer car;
		if (! SymbolName (car, aliasHack))
			return false;
		output.append (car);

		Buffer cdr;
		if (TypedQualifiedName (cdr))
		{
			if (!foldDefaults || !locatePattern (car.slice, cdr.slice) == 0)
			{
				output.append (".");
				output.append (cdr);
			}
		}

		return true;
	}

	bool SymbolName (ref Buffer output, bool aliasHack = false)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace (aliasHack ? "SymbolNameAH" : "SymbolName");

// 		if (TemplateInstanceName (output))
// 			return true;

		if (aliasHack)
		{
			if (LNameAliasHack (output))
				return true;
		}
		else
		{
			if (LName (output))
				return true;
		}

		return false;
	}

	bool LName (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("LName");
		//try
		//{
			uint chars;
			if (! Number (chars))
				return false;

			char[] original = input;
			input = input[0 .. chars];
			uint len = input.length;
			Buffer buf;
			if (TemplateInstanceName (buf))
			{
				output.append (buf);
				input = original[len - input.length .. $];
				return true;
			}
			input = original;

			return Name (chars, output);
/+		}
		catch (Exception e)
		{
			debug(traceDemangler) report ("\033[1;31mException : {} @ {}:{}\033[0m", e.msg, e.file, e.line);
			return false;
		}+/
	}

	/* this hack is ugly and guaranteed to break, but the symbols
	   generated for template alias parameters are broken:
	   the compiler generates a symbol of the form S(number){(number)(name)}
	   with no space between the numbers; what we do is try to match
	   different combinations of division between the concatenated numbers */

	bool LNameAliasHack (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("LNameAH");
		
// 		uint chars;
// 		if (! Number (chars))
// 			return false;

		uint chars;
		Buffer number;
		if (! NumberNoParse (number))
			return false;
		char[] str = number.slice;
		int i = 0;

		bool done = false;

		char[] original = input;
		char[] working = input;

		while (done == false)
		{
			if (i > 0)
			{
				input = working = original[0 .. to!(uint)(str[0..i])];
			}
			else
				input = working = original;

			chars = to!(uint)(str[i..$]);

			if (chars < input.length && chars > 0)
			{
				// cut the string from the right side to the number
				//char[] original = input;
				//input = input[0 .. chars];
				//uint len = input.length;
				debug(traceDemangler) report ("trying {}/{}", chars, input.length);
				Buffer buf;
				done = TemplateInstanceName (buf);
				//input = original[len - input.length .. $];

				if (done)
				{
					output.append (buf);
				}
				else
				{
					input = working;
					debug(traceDemangler) report ("trying {}/{}", chars, input.length);
					done = Name (chars, buf);
					if (done)
						output.append (buf);
				}

				if (done)
				{
					input = original[working.length - input.length .. $];
					return true;
				}
				else
					input = original;
			}

			i += 1;
			if (i == str.length)
				return false;
		}

		return true;
	}

	bool Number (ref uint value)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Number");

		if (input.length == 0)
			return false;
	
		value = 0;
		if (input[0] >= '0' && input[0] <= '9')
		{
			while (input.length > 0 && input[0] >= '0' && input[0] <= '9')
			{
				value = value * 10 + cast(uint) (input[0] - '0');
				consume (1);
			}
			return true;
		}
		else
			return false;
	}

	bool NumberNoParse (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("NumberNP");
	
		if (input.length == 0)
			return false;

		if (input[0] >= '0' && input[0] <= '9')
		{
			while (input.length > 0 && input[0] >= '0' && input[0] <= '9')
			{
				output.append (input[0]);
				consume (1);
			}
			return true;
		}
		else
			return false;
	}

	bool Name (uint count, ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Name");

		//if (input.length >= 3 && input[0 .. 3] == "__T")
		//	return false; // workaround

		if (count > input.length)
			return false;

		char[] name = consume (count);
		output.append (name);
		debug(traceDemangler) report (">>> name={}", name);

		return count > 0;
	}

	bool Type (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Type");

		Buffer subtype;

		switch (input[0])
		{
			case 'x':
				consume (1);
				output.append ("const ");
				return Type (output);

			case 'y':
				consume (1);
				output.append ("invariant ");
				return Type (output);

			case 'A':
				consume (1);
				if (Type (subtype))
				{
					output.append (subtype);
					output.append ("[]");
					return true;
				}
				return false;

			case 'G':
				consume (1);
				uint size;
				if (! Number (size))
					return false;
				if (Type (subtype))
				{
					output.append (subtype);
					output.append ("[" ~ to!(char[])(size) ~ "]");
					return true;
				}
				return false;

			case 'H':
				consume (1);
				Buffer keytype;
				if (! Type (keytype))
					return false;
				if (Type (subtype))
				{
					output.append (subtype);
					output.append ("[");
					output.append (keytype);
					output.append ("]");
					return true;
				}
				return false;

			case 'P':
				consume (1);
				if (Type (subtype))
				{
					output.append (subtype);
					output.append ("*");
					return true;
				}
				return false;

			case 'F': case 'U': case 'W': case 'V': case 'R': case 'D': case 'M':
				return TypeFunction (output);

			case 'I': case 'C': case 'S': case 'E': case 'T':
				return TypeNamed (output);

			case 'n':
				consume (1);
				output.append ("none");
				return true;

			case 'v':
				consume (1);
				output.append ("void");
				return true;

			case 'g':
				consume (1);
				output.append ("byte");
				return true;

			case 'h':
				consume (1);
				output.append ("ubyte");
				return true;

			case 's':
				consume (1);
				output.append ("short");
				return true;

			case 't':
				consume (1);
				output.append ("ushort");
				return true;

			case 'i':
				consume (1);
				output.append ("int");
				return true;

			case 'k':
				consume (1);
				output.append ("uint");
				return true;

			case 'l':
				consume (1);
				output.append ("long");
				return true;

			case 'm':
				consume (1);
				output.append ("ulong");
				return true;

			case 'f':
				consume (1);
				output.append ("float");
				return true;

			case 'd':
				consume (1);
				output.append ("double");
				return true;

			case 'e':
				consume (1);
				output.append ("real");
				return true;

			/* TODO: imaginary and complex types */

			case 'b':
				consume (1);
				output.append ("bool");
				return true;

			case 'a':
				consume (1);
				output.append ("char");
				return true;

			case 'u':
				consume (1);
				output.append ("wchar");
				return true;

			case 'w':
				consume (1);
				output.append ("dchar");
				return true;

			case 'B':
				consume (1);
				uint count;
				if (! Number (count))
					return false;
				output.append ('(');
				if (! Arguments (output))
					return false;
				output.append (')');
				return true;

			default:
				return false;
		}

		return true;
	}

	bool TypeFunction (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TypeFunction");

		bool isMethod = false;
		bool isDelegate = false;

		if (input.length == 0)
			return false;

		if (input[0] == 'M')
		{
			consume (1);
			isMethod = true;
		}

		if (input[0] == 'D')
		{
			consume (1);
			isDelegate = true;
			assert (! isMethod);
		}

		switch (input[0])
		{
			case 'F':
				consume (1);
				break;

			case 'U':
			 	consume (1);
			 	output.append ("extern(C) ");
			 	break;

			case 'W':
			 	consume (1);
			 	output.append ("extern(Windows) ");
			 	break;

			case 'V':
			 	consume (1);
			 	output.append ("extern(Pascal) ");
			 	break;

			case 'R':
			 	consume (1);
			 	output.append ("extern(C++) ");
			 	break;

			default:
				return false;
		}

		Buffer args;
		Arguments (args);

		switch (input[0])
		{
			case 'X': case 'Y': case 'Z':
				consume (1);
				break;
			default:
				return false;
		}

		Buffer ret;
		if (! Type (ret))
			return false;

		output.append (ret);
		//output.append (" ");
		
		if (isMethod)
			output.append (" method (");
		else if (isDelegate)
			output.append (" delegate (");
		else
			output.append (" function (");

		//output.append (" (");
		output.append (args);
		output.append (")");

		return true;
	}

	bool Arguments (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Arguments");

		Buffer car;
		if (! Argument (car))
			return false;
		output.append (car);

		Buffer cdr;
		if (Arguments (cdr))
		{
			output.append (", ");
			output.append (cdr);
		}

		return true;
	}

	bool Argument (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Argument");

		if (input.length == 0)
			return false;

		switch (input[0])
		{
			case 'K':
				consume (1);
				output.append ("inout ");
				break;

			case 'J':
				consume (1);
				output.append ("out ");
				break;

			case 'L':
				consume (1);
				output.append ("lazy ");
				break;
				
			default:
		}

		if (! Type (output))
			return false;
			
		return true;
	}

	bool TypeNamed (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TypeNamed");

		char[] kind;
		switch (input[0])
		{
			case 'I':
				consume (1);
				kind = "interface";
				break;
				
			case 'S':
				consume (1);
				kind = "struct";
				break;
			
			case 'C':
				consume (1);
				kind = "class";
				break;
			
			case 'E':
				consume (1);
				kind = "enum";
				break;
			
			case 'T':
				consume (1);
				kind = "typedef";
				break;
				
			default:
				return false;
		}

		//output.append (kind);
		//output.append ("=");

		if (! QualifiedName (output))
			return false;

		if (printTypeKind)
		{
			output.append ("<");
			output.append (kind);
			output.append (">");
		}
			
		return true;
	}

	bool TemplateInstanceName (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TemplateInstanceName");

		if (input.length < 4 || input[0..3] != "__T")
			return false;

		consume (3);

		if (! LName (output))
			return false;

		output.append ("!(");

		_templateDepth++;
		if (_templateDepth <= templateExpansionDepth)
			TemplateArgs (output);
		else
		{
			Buffer throwaway;
			TemplateArgs (throwaway);
			output.append ("...");
		}
		_templateDepth--;

		if (input.length > 0 && input[0] != 'Z')
			return false;

		output.append (")");
		
		consume (1);
		return true;
	}

	bool TemplateArgs (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TemplateArgs");

		Buffer car;
		if (! TemplateArg (car))
			return false;
		output.append (car);

		Buffer cdr;
		if (TemplateArgs (cdr))
		{
			output.append (", ");
			output.append (cdr);
		}

		return true;
	}

	bool TemplateArg (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("TemplateArg");

		if (input.length == 0)
			return false;

		switch (input[0])
		{
			case 'T':
				consume (1);
				if (! Type (output))
					return false;
				return true;

			case 'V':
				consume (1);
				Buffer throwaway;
				if (! Type (throwaway))
					return false;
				if (! Value (output))
					return false;
				return true;

			case 'S':
				consume (1);
				if (! QualifiedName (output, true))
					return false;
				return true;

			default:
				return false;
		}

		return false;
	}

	bool Value (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("Value");

		if (input.length == 0)
			return false;

		switch (input[0])
		{
			case 'n':
				consume (1);
				return true;

			case 'N':
				consume (1);
				output.append ('-');
				if (! NumberNoParse (output))
					return false;
				return true;

			case 'e':
				consume (1);
				if (! HexFloat (output))
					return false;
				return true;

			case 'c': //TODO

			case 'A':
				consume (1);
				uint count;
				if (! Number (count))
					return false;
				output.append ("[");
				for (uint i = 0; i < count-1; i++)
				{
					if (! Value (output))
						return false;
					output.append (", ");
				}
				if (! Value (output))
					return false;
				output.append ("]");
				return true;

			default:
				if (! NumberNoParse (output))
					return false;
				return true;
		}

		return false;
	}

	bool HexFloat (ref Buffer output)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("HexFloat");

		if (input[0 .. 3] == "NAN")
		{
			consume (3);
			output.append ("nan");
			return true;
		}
		else if (input[0 .. 3] == "INF")
		{
			consume (3);
			output.append ("+inf");
			return true;
		}
		else if (input[0 .. 3] == "NINF")
		{
			consume (3);
			output.append ("-inf");
			return true;
		}

		bool negative = false;
		if (input[0] == 'N')
		{
			consume (1);
			negative = true;
		}

		ulong num;
		if (! HexNumber (num))
			return false;

		if (input[0] != 'P')
			return false;

		bool negative_exponent = false;
		if (input[0] == 'N')
		{
			consume (1);
			negative_exponent = true;
		}

		uint exponent;
		if (! Number (exponent))
			return false;

		return true;
	}

	static bool isHexDigit (char c)
	{
		return (c > '0' && c <'9') || (c > 'a' && c < 'f') || (c > 'A' && c < 'F');
	}

	bool HexNumber (ref ulong value)
	out (result)
	{
		debug(traceDemangler) trace (result);
	}
	body
	{
		debug(traceDemangler) trace ("HexFloat");

		if (isHexDigit (input[0]))
		{
			while (isHexDigit (input[0]))
			{
				//output.append (input[0]);
				consume (1);
			}
			return true;
		}
		else
			return false;
	}
}

private struct Buffer
{
	char[4096] data;
	size_t     length;

	void append (char[] s)
	{
		data[this.length .. this.length + s.length] = s;
		this.length += s.length;
	}

	void append (char c)
	{
		data[this.length .. this.length + 1] = c;
		this.length += 1;
	}

	void append (Buffer b)
	{
		append (b.slice);
	}

	char[] slice ()
	{
		return data[0 .. this.length];
	}
}#line 2 "parts/DbgInfo.di"
import tango.text.Util;
import tango.stdc.stdio;
import tango.stdc.stringz;
import tango.stdc.string : strcpy;
import tango.sys.win32.CodePage;
import tango.core.Exception;



struct AddrDebugInfo {
	align(1) {
		size_t	addr;
		char*	file;
		char*	func;
		ushort	line;
	}
}

class ModuleDebugInfo {
	AddrDebugInfo[]	debugInfo;
	uint						debugInfoLen;
	size_t[char*]			fileMaxAddr;
	char*[]					strBuffer;
	uint						strBufferLen;
	
	void addDebugInfo(size_t addr, char* file, char* func, ushort line) {
		debugInfo.append(AddrDebugInfo(addr, file, func, line), &debugInfoLen);

		if (auto a = file in fileMaxAddr) {
			if (addr > *a) *a = addr;
		} else {
			fileMaxAddr[file] = addr;
		}
	}
	
	char* bufferString(char[] str) {
		char[] res;
		res.alloc(str.length+1, false);
		res[0..$-1] = str[];
		res[str.length] = 0;
		strBuffer.append(res.ptr, &strBufferLen);
		return res.ptr;
	}
	
	void freeArrays() {
		debugInfo.free();
		debugInfoLen = 0;

		fileMaxAddr = null;
		foreach (ref s; strBuffer[0..strBufferLen]) {
			cFree(s);
		}
		strBuffer.free();
		strBufferLen = 0;
	}
	
	ModuleDebugInfo	prev;
	ModuleDebugInfo	next;
}

class GlobalDebugInfo {
	ModuleDebugInfo	head;
	ModuleDebugInfo	tail;
	
	
	synchronized int opApply(int delegate(ref ModuleDebugInfo) dg) {
		for (auto it = head; it !is null; it = it.next) {
			if (auto res = dg(it)) {
				return res;
			}
		}
		return 0;
	}
	
	
	synchronized void addDebugInfo(ModuleDebugInfo info) {
		if (head is null) {
			head = tail = info;
			info.next = info.prev = null;
		} else {
			tail.next = info;
			info.prev = tail;
			info.next = null;
			tail = info;
		}
	}
	
	
	synchronized void removeDebugInfo(ModuleDebugInfo info) {
		assert (info !is null);
		assert (info.next !is null || info.prev !is null || head is info);
		
		if (info is head) {
			head = head.next;
		}
		if (info is tail) {
			tail = tail.prev;
		}
		if (info.prev) {
			info.prev.next = info.next;
		}
		if (info.next) {
			info.next.prev = info.prev;
		}
		info.freeArrays;
		info.prev = info.next = null;
		
		delete info;
	}
}

private GlobalDebugInfo globalDebugInfo;
static this() {
	globalDebugInfo = new GlobalDebugInfo;
}

void initHostExecutableDebugInfo(char[] progName) {
	scope info = new DebugInfo(progName);
	// we'll let it die now :)
}


AddrDebugInfo getAddrDbgInfo(size_t a) {
    AddrDebugInfo min_line;
    int min_diff = 0x7fffffff;
    
    foreach (modInfo; globalDebugInfo) {
		bool local = false;
		
		foreach (l; modInfo.debugInfo[0 .. modInfo.debugInfoLen]) {
			int diff = a - l.addr;

			// '2' is a hack here; the symbols found were always off...
			if (diff < 2) continue;
			if (diff < min_diff) {
				min_diff = diff;
				min_line = l;
				local = true;
			}
		}
		
		if (local) {
			if (min_diff > 0x100) {
				min_line = min_line.init;
				min_diff = 0x7fffffff;
			}
			else {
				if (auto ma = min_line.file in modInfo.fileMaxAddr) {
					// '2' is a hack here; the symbols found were always off...
					if (a > *ma+2) {
						min_line = min_line.init;
						min_diff = 0x7fffffff;
					}
				} else {
					printf("there ain't '%s' in fileMaxAddr\n", min_line.file);
					min_line = min_line.init;
					min_diff = 0x7fffffff;
				}
			}
		}
	}
    return min_line;
}

   

class DebugInfo {
	ModuleDebugInfo info;
	
	
	this(char[] filename) {
		info = new ModuleDebugInfo;
		ParseCVFile(filename);
		assert (globalDebugInfo !is null);
		globalDebugInfo.addDebugInfo(info);
	}
	 
	private {
		int ParseCVFile(char[] filename) {
			FILE* debugfile;

			if (filename == "") return (-1);

			//try {
				debugfile = fopen((filename ~ \0).ptr, "rb");
			/+} catch(Exception e){
				return -1;
			}+/

			if (!ParseFileHeaders (debugfile)) return -1;

			g_secthdrs.length = g_nthdr.FileHeader.NumberOfSections;

			if (!ParseSectionHeaders (debugfile)) return -1;

			g_debugdirs.length = g_nthdr.OptionalHeader.DataDirectory[IMAGE_FILE_DEBUG_DIRECTORY].Size /
				IMAGE_DEBUG_DIRECTORY.sizeof;

			if (!ParseDebugDir (debugfile)) return -1;
			if (g_dwStartOfCodeView == 0) return -1;
			if (!ParseCodeViewHeaders (debugfile)) return -1;
			if (!ParseAllModules (debugfile)) return -1;

			g_dwStartOfCodeView = 0;
			g_exe_mode = true;
			g_secthdrs = null;
			g_debugdirs = null;
			g_cvEntries = null;
			g_cvModules = null;
			g_filename = null;
			g_filenameStringz = null;

			fclose(debugfile);
			return 0;
		}
			
		bool ParseFileHeaders(FILE* debugfile) {
			CVHeaderType hdrtype;

			hdrtype = GetHeaderType (debugfile);

			if (hdrtype == CVHeaderType.DOS) {
				if (!ReadDOSFileHeader (debugfile, &g_doshdr))return false;
				hdrtype = GetHeaderType (debugfile);
			}
			if (hdrtype == CVHeaderType.NT) {
				if (!ReadPEFileHeader (debugfile, &g_nthdr)) return false;
			}

			return true;
		}
			
		CVHeaderType GetHeaderType(FILE* debugfile) {
			ushort hdrtype;
			CVHeaderType ret = CVHeaderType.NONE;

			int oldpos = ftell(debugfile);

			if (!ReadChunk (debugfile, &hdrtype, ushort.sizeof, -1)){
				fseek(debugfile, oldpos, SEEK_SET);
				return CVHeaderType.NONE;
			}

			if (hdrtype == 0x5A4D) 	     // "MZ"
				ret = CVHeaderType.DOS;
			else if (hdrtype == 0x4550)  // "PE"
				ret = CVHeaderType.NT;
			else if (hdrtype == 0x4944)  // "DI"
				ret = CVHeaderType.DBG;

			fseek(debugfile, oldpos, SEEK_SET);

			return ret;
		}
		 
		/*
		 * Extract the DOS file headers from an executable
		 */
		bool ReadDOSFileHeader(FILE* debugfile, IMAGE_DOS_HEADER *doshdr) {
			uint bytes_read;

			bytes_read = fread(doshdr, 1, IMAGE_DOS_HEADER.sizeof, debugfile);
			if (bytes_read < IMAGE_DOS_HEADER.sizeof){
				return false;
			}

			// Skip over stub data, if present
			if (doshdr.e_lfanew) {
				fseek(debugfile, doshdr.e_lfanew, SEEK_SET);
			}

			return true;
		}
		 
		/*
		 * Extract the DOS and NT file headers from an executable
		 */
		bool ReadPEFileHeader(FILE* debugfile, IMAGE_NT_HEADERS *nthdr) {
			uint bytes_read;

			bytes_read = fread(nthdr, 1, IMAGE_NT_HEADERS.sizeof, debugfile);
			if (bytes_read < IMAGE_NT_HEADERS.sizeof) {
				return false;
			}

			return true;
		}
		  
		bool ParseSectionHeaders(FILE* debugfile) {
			if (!ReadSectionHeaders (debugfile, g_secthdrs)) return false;
			return true;
		}
			
		bool ReadSectionHeaders(FILE* debugfile, inout IMAGE_SECTION_HEADER[] secthdrs) {
			for(int i=0;i<secthdrs.length;i++){
				uint bytes_read;
				bytes_read = fread((&secthdrs[i]), 1, IMAGE_SECTION_HEADER.sizeof, debugfile);
				if (bytes_read < 1){
					return false;
				}
			}
			return true;
		}
		  
		bool ParseDebugDir(FILE* debugfile) {
			int i;
			int filepos;

			if (g_debugdirs.length == 0) return false;

			filepos = GetOffsetFromRVA (g_nthdr.OptionalHeader.DataDirectory[IMAGE_FILE_DEBUG_DIRECTORY].VirtualAddress);

			fseek(debugfile, filepos, SEEK_SET);

			if (!ReadDebugDir (debugfile, g_debugdirs)) return false;

			for (i = 0; i < g_debugdirs.length; i++) {
				enum {
					IMAGE_DEBUG_TYPE_CODEVIEW = 2,
				}

				if (g_debugdirs[i].Type == IMAGE_DEBUG_TYPE_CODEVIEW) {
					g_dwStartOfCodeView = g_debugdirs[i].PointerToRawData;
				}
			}

			g_debugdirs = null;

			return true;
		}
			
		// Calculate the file offset, based on the RVA.
		uint GetOffsetFromRVA(uint rva) {
			int i;
			uint sectbegin;

			for (i = g_secthdrs.length - 1; i >= 0; i--) {
				sectbegin = g_secthdrs[i].VirtualAddress;
				if (rva >= sectbegin) break;
			}
			uint offset = g_secthdrs[i].VirtualAddress - g_secthdrs[i].PointerToRawData;
			uint filepos = rva - offset;
			return filepos;
		}
		 
		// Load in the debug directory table.  This directory describes the various
		// blocks of debug data that reside at the end of the file (after the COFF
		// sections), including FPO data, COFF-style debug info, and the CodeView
		// we are *really* after.
		bool ReadDebugDir(FILE* debugfile, inout IMAGE_DEBUG_DIRECTORY debugdirs[]) {
			uint bytes_read;
			for(int i=0;i<debugdirs.length;i++) {
				bytes_read = fread((&debugdirs[i]), 1, IMAGE_DEBUG_DIRECTORY.sizeof, debugfile);
				if (bytes_read < IMAGE_DEBUG_DIRECTORY.sizeof) {
					return false;
				}
			}
			return true;
		}
		  
		bool ParseCodeViewHeaders(FILE* debugfile) {
			fseek(debugfile, g_dwStartOfCodeView, SEEK_SET);
			if (!ReadCodeViewHeader (debugfile, g_cvSig, g_cvHeader)) return false;
			g_cvEntries.length = g_cvHeader.cDir;
			if (!ReadCodeViewDirectory (debugfile, g_cvEntries)) return false;
			return true;
		}

			
		bool ReadCodeViewHeader(FILE* debugfile, out OMFSignature sig, out OMFDirHeader dirhdr) {
			uint bytes_read;

			bytes_read = fread((&sig), 1, OMFSignature.sizeof, debugfile);
			if (bytes_read < OMFSignature.sizeof){
				return false;
			}

			fseek(debugfile, sig.filepos + g_dwStartOfCodeView, SEEK_SET);
			bytes_read = fread((&dirhdr), 1, OMFDirHeader.sizeof, debugfile);
			if (bytes_read < OMFDirHeader.sizeof){
				return false;
			}
			return true;
		}
		 
		bool ReadCodeViewDirectory(FILE* debugfile, inout OMFDirEntry[] entries) {
			uint bytes_read;

			for(int i=0;i<entries.length;i++){
				bytes_read = fread((&entries[i]), 1, OMFDirEntry.sizeof, debugfile);
				if (bytes_read < OMFDirEntry.sizeof){
					return false;
				}
			}
			return true;
		}
		  
		bool ParseAllModules (FILE* debugfile) {
			if (g_cvHeader.cDir == 0){
				return true;
			}

			if (g_cvEntries.length == 0){
				return false;
			}

			fseek(debugfile, g_dwStartOfCodeView + g_cvEntries[0].lfo, SEEK_SET);

			if (!ReadModuleData (debugfile, g_cvEntries, g_cvModules)){
				return false;
			}


			for (int i = 0; i < g_cvModules.length; i++){
				ParseRelatedSections (i, debugfile);
			}

			return true;
		}

			
		bool ReadModuleData(FILE* debugfile, OMFDirEntry[] entries, out OMFModuleFull[] modules) {
			uint bytes_read;
			int pad;

			int module_bytes = (ushort.sizeof * 3) + (char.sizeof * 2);

			if (entries == null) return false;

			modules.length = 0;

			for (int i = 0; i < entries.length; i++){
				if (entries[i].SubSection == sstModule)
					modules.length = modules.length + 1;
			}

			for (int i = 0; i < modules.length; i++){

				bytes_read = fread((&modules[i]), 1, module_bytes, debugfile);
				if (bytes_read < module_bytes){
					return false;
				}

				int segnum = modules[i].cSeg;
				OMFSegDesc[] segarray;
				segarray.length=segnum;
				for(int j=0;j<segnum;j++){
					bytes_read =  fread((&segarray[j]), 1, OMFSegDesc.sizeof, debugfile);
					if (bytes_read < OMFSegDesc.sizeof){
						return false;
					}
				}
				modules[i].SegInfo = segarray.ptr;

				char namelen;
				bytes_read = fread((&namelen), 1, char.sizeof, debugfile);
				if (bytes_read < 1){
					return false;
				}

				pad = ((namelen + 1) % 4);
				if (pad) namelen += (4 - pad);

				modules[i].Name = (new char[namelen+1]).ptr;
				modules[i].Name[namelen]=0;
				bytes_read = fread((modules[i].Name), 1, namelen, debugfile);
				if (bytes_read < namelen){
					return false;
				}
			}
			return true;
		}
		 
		bool ParseRelatedSections(int index, FILE* debugfile) {
			int i;

			if (g_cvEntries == null)
				return false;

			for (i = 0; i < g_cvHeader.cDir; i++){
				if (g_cvEntries[i].iMod != (index + 1) ||
					g_cvEntries[i].SubSection == sstModule)
					continue;

				switch (g_cvEntries[i].SubSection){
				case sstSrcModule:
					ParseSrcModuleInfo (i, debugfile);
					break;
				default:
					break;
				}
			}

			return true;
		}
			
		bool ParseSrcModuleInfo (int index, FILE* debugfile) {
			int i;

			byte *rawdata;
			byte *curpos;
			short filecount;
			short segcount;

			int moduledatalen;
			int filedatalen;
			int linedatalen;

			if (g_cvEntries == null || debugfile == null ||
				g_cvEntries[index].SubSection != sstSrcModule)
				return false;

			int fileoffset = g_dwStartOfCodeView + g_cvEntries[index].lfo;

			rawdata = (new byte[g_cvEntries[index].cb]).ptr;
			if (!rawdata) return false;

			if (!ReadChunk (debugfile, rawdata, g_cvEntries[index].cb, fileoffset)) return false;
			uint[] baseSrcFile;
			ExtractSrcModuleInfo (rawdata, &filecount, &segcount,baseSrcFile);

			for(i=0;i<baseSrcFile.length;i++){
				uint baseSrcLn[];
				ExtractSrcModuleFileInfo (rawdata+baseSrcFile[i],baseSrcLn);
				for(int j=0;j<baseSrcLn.length;j++){
					ExtractSrcModuleLineInfo (rawdata+baseSrcLn[j], j);
				}
			}

			return true;
		}
		
		void ExtractSrcModuleInfo (byte* rawdata, short *filecount, short *segcount,out uint[] fileinfopos) {
			int i;
			int datalen;

			ushort cFile;
			ushort cSeg;
			uint *baseSrcFile;
			uint *segarray;
			ushort *segindexarray;

			cFile = *cast(short*)rawdata;
			cSeg = *cast(short*)(rawdata + 2);
			baseSrcFile = cast(uint*)(rawdata + 4);
			segarray = &baseSrcFile[cFile];
			segindexarray = cast(ushort*)(&segarray[cSeg * 2]);

			*filecount = cFile;
			*segcount = cSeg;

			fileinfopos.length=cFile;
			for (i = 0; i < cFile; i++) {
				fileinfopos[i]=baseSrcFile[i];
			}
		}
		 
		void ExtractSrcModuleFileInfo(byte* rawdata,out uint[] offset) {
			int i;
			int datalen;

			ushort cSeg;
			uint *baseSrcLn;
			uint *segarray;
			byte cFName;

			cSeg = *cast(short*)(rawdata);
			// Skip the 'pad' field
			baseSrcLn = cast(uint*)(rawdata + 4);
			segarray = &baseSrcLn[cSeg];
			cFName = *(cast(byte*)&segarray[cSeg*2]);

			g_filename = (cast(char*)&segarray[cSeg*2] + 1)[0..cFName].dup;
			g_filenameStringz = info.bufferString(g_filename);

			offset.length=cSeg;
			for (i = 0; i < cSeg; i++){
				offset[i]=baseSrcLn[i];
			}
		}
		 
		void ExtractSrcModuleLineInfo(byte* rawdata, int tablecount) {
			int i;

			ushort Seg;
			ushort cPair;
			uint *offset;
			ushort *linenumber;

			Seg = *cast(ushort*)rawdata;
			cPair = *cast(ushort*)(rawdata + 2);
			offset = cast(uint*)(rawdata + 4);
			linenumber = cast(ushort*)&offset[cPair];

			uint base=0;
			if (Seg != 0){
				base = g_nthdr.OptionalHeader.ImageBase+g_secthdrs[Seg-1].VirtualAddress;
			}
			
			for (i = 0; i < cPair; i++) {
				uint address = offset[i]+base;
				info.addDebugInfo(address, g_filenameStringz, null, linenumber[i]);
			}
		}

		   
		bool ReadChunk(FILE* debugfile, void *dest, int length, int fileoffset) {
			uint bytes_read;

			if (fileoffset >= 0) {
				fseek(debugfile, fileoffset, SEEK_SET);
			}

			bytes_read = fread(dest, 1, length, debugfile);
			if (bytes_read < length) {
				return false;
			}

			return true;
		}


		enum CVHeaderType : int {
			NONE,
			DOS,
			NT,
			DBG
		}

		int g_dwStartOfCodeView = 0;

		bool g_exe_mode = true;
		IMAGE_DOS_HEADER g_doshdr;
		IMAGE_SEPARATE_DEBUG_HEADER g_dbghdr;
		IMAGE_NT_HEADERS g_nthdr;

		IMAGE_SECTION_HEADER g_secthdrs[];

		IMAGE_DEBUG_DIRECTORY g_debugdirs[];
		OMFSignature g_cvSig;
		OMFDirHeader g_cvHeader;
		OMFDirEntry g_cvEntries[];
		OMFModuleFull g_cvModules[];
		char[] g_filename;
		char* g_filenameStringz;
	}
}




enum {
	IMAGE_FILE_DEBUG_DIRECTORY = 6
}
 
enum {
	sstModule			= 0x120,
	sstSrcModule		= 0x127,
	sstGlobalPub		= 0x12a,
}
 
struct OMFSignature {
	char	Signature[4];
	int	filepos;
}
 
struct OMFDirHeader {
	ushort	cbDirHeader;
	ushort	cbDirEntry;
	uint	cDir;
	int		lfoNextDir;
	uint	flags;
}
 
struct OMFDirEntry {
	ushort	SubSection;
	ushort	iMod;
	int		lfo;
	uint	cb;
}
  
struct OMFSegDesc {
	ushort	Seg;
	ushort	pad;
	uint	Off;
	uint	cbSeg;
}
 
struct OMFModule {
	ushort	ovlNumber;
	ushort	iLib;
	ushort	cSeg;
	char			Style[2];
}
 
struct OMFModuleFull {
	ushort	ovlNumber;
	ushort	iLib;
	ushort	cSeg;
	char			Style[2];
	OMFSegDesc		*SegInfo;
	char			*Name;
}
	
struct OMFSymHash {
	ushort	symhash;
	ushort	addrhash;
	uint	cbSymbol;
	uint	cbHSym;
	uint	cbHAddr;
}
 
struct DATASYM16 {
		ushort reclen;	// Record length
		ushort rectyp;	// S_LDATA or S_GDATA
		int off;		// offset of symbol
		ushort seg;		// segment of symbol
		ushort typind;	// Type index
		byte name[1];	// Length-prefixed name
}
typedef DATASYM16 PUBSYM16;
 

struct IMAGE_DOS_HEADER {      // DOS .EXE header
    ushort   e_magic;                     // Magic number
    ushort   e_cblp;                      // Bytes on last page of file
    ushort   e_cp;                        // Pages in file
    ushort   e_crlc;                      // Relocations
    ushort   e_cparhdr;                   // Size of header in paragraphs
    ushort   e_minalloc;                  // Minimum extra paragraphs needed
    ushort   e_maxalloc;                  // Maximum extra paragraphs needed
    ushort   e_ss;                        // Initial (relative) SS value
    ushort   e_sp;                        // Initial SP value
    ushort   e_csum;                      // Checksum
    ushort   e_ip;                        // Initial IP value
    ushort   e_cs;                        // Initial (relative) CS value
    ushort   e_lfarlc;                    // File address of relocation table
    ushort   e_ovno;                      // Overlay number
    ushort   e_res[4];                    // Reserved words
    ushort   e_oemid;                     // OEM identifier (for e_oeminfo)
    ushort   e_oeminfo;                   // OEM information; e_oemid specific
    ushort   e_res2[10];                  // Reserved words
    int      e_lfanew;                    // File address of new exe header
}
 
struct IMAGE_FILE_HEADER {
    ushort    Machine;
    ushort    NumberOfSections;
    uint      TimeDateStamp;
    uint      PointerToSymbolTable;
    uint      NumberOfSymbols;
    ushort    SizeOfOptionalHeader;
    ushort    Characteristics;
}
 
struct IMAGE_SEPARATE_DEBUG_HEADER {
    ushort        Signature;
    ushort        Flags;
    ushort        Machine;
    ushort        Characteristics;
    uint       TimeDateStamp;
    uint       CheckSum;
    uint       ImageBase;
    uint       SizeOfImage;
    uint       NumberOfSections;
    uint       ExportedNamesSize;
    uint       DebugDirectorySize;
    uint       SectionAlignment;
    uint       Reserved[2];
}
 
struct IMAGE_DATA_DIRECTORY {
    uint   VirtualAddress;
    uint   Size;
}
 
struct IMAGE_OPTIONAL_HEADER {
    //
    // Standard fields.
    //

    ushort    Magic;
    byte    MajorLinkerVersion;
    byte    MinorLinkerVersion;
    uint   SizeOfCode;
    uint   SizeOfInitializedData;
    uint   SizeOfUninitializedData;
    uint   AddressOfEntryPoint;
    uint   BaseOfCode;
    uint   BaseOfData;

    //
    // NT additional fields.
    //

    uint   ImageBase;
    uint   SectionAlignment;
    uint   FileAlignment;
    ushort    MajorOperatingSystemVersion;
    ushort    MinorOperatingSystemVersion;
    ushort    MajorImageVersion;
    ushort    MinorImageVersion;
    ushort    MajorSubsystemVersion;
    ushort    MinorSubsystemVersion;
    uint   Win32VersionValue;
    uint   SizeOfImage;
    uint   SizeOfHeaders;
    uint   CheckSum;
    ushort    Subsystem;
    ushort    DllCharacteristics;
    uint   SizeOfStackReserve;
    uint   SizeOfStackCommit;
    uint   SizeOfHeapReserve;
    uint   SizeOfHeapCommit;
    uint   LoaderFlags;
    uint   NumberOfRvaAndSizes;

	enum {
		IMAGE_NUMBEROF_DIRECTORY_ENTRIES = 16,
	}

    IMAGE_DATA_DIRECTORY DataDirectory[IMAGE_NUMBEROF_DIRECTORY_ENTRIES];
}
 
struct IMAGE_NT_HEADERS {
    uint Signature;
    IMAGE_FILE_HEADER FileHeader;
    IMAGE_OPTIONAL_HEADER OptionalHeader;
}
 
enum {
	IMAGE_SIZEOF_SHORT_NAME = 8,
}

struct IMAGE_SECTION_HEADER {
    byte    Name[IMAGE_SIZEOF_SHORT_NAME];//8
    union misc{
            uint   PhysicalAddress;
            uint   VirtualSize;//12
    }
	misc Misc;
    uint   VirtualAddress;//16
    uint   SizeOfRawData;//20
    uint   PointerToRawData;//24
    uint   PointerToRelocations;//28
    uint   PointerToLinenumbers;//32
    ushort NumberOfRelocations;//34
    ushort NumberOfLinenumbers;//36
    uint   Characteristics;//40
}
 
struct IMAGE_DEBUG_DIRECTORY {
    uint   Characteristics;
    uint   TimeDateStamp;
    ushort MajorVersion;
    ushort MinorVersion;
    uint   Type;
    uint   SizeOfData;
    uint   AddressOfRawData;
    uint   PointerToRawData;
}
 
struct OMFSourceLine {
	ushort	Seg;
	ushort	cLnOff;
	uint	offset[1];
	ushort	lineNbr[1];
}
 
struct OMFSourceFile {
	ushort	cSeg;
	ushort	reserved;
	uint	baseSrcLn[1];
	ushort	cFName;
	char	Name;
}
 
struct OMFSourceModule {
	ushort	cFile;
	ushort	cSeg;
	uint	baseSrcFile[1];
}
#line 2 "parts/CInterface.di"
extern (C) {
	ModuleDebugInfo ModuleDebugInfo_new() {
		return new ModuleDebugInfo;
	}
	
	void ModuleDebugInfo_addDebugInfo(ModuleDebugInfo minfo, size_t addr, char* file, char* func, ushort line) {
		minfo.addDebugInfo(addr, file, func, line);
	}
	
	char* ModuleDebugInfo_bufferString(ModuleDebugInfo minfo, char[] str) {
		char[] res;
		res.alloc(str.length+1, false);
		res[0..$-1] = str[];
		res[str.length] = 0;
		minfo.strBuffer.append(res.ptr, &minfo.strBufferLen);
		return res.ptr;
	}
	
	void GlobalDebugInfo_addDebugInfo(ModuleDebugInfo minfo) {
		globalDebugInfo.addDebugInfo(minfo);
	}
	
	void GlobalDebugInfo_removeDebugInfo(ModuleDebugInfo minfo) {
		globalDebugInfo.removeDebugInfo(minfo);
	}
}
static this() {
	loadWinAPIFunctions();
	
	char modNameBuf[512] = 0;
	int modNameLen = GetModuleFileNameExA(GetCurrentProcess(), null, modNameBuf.ptr, modNameBuf.length-1);
	char[] modName = modNameBuf[0..modNameLen];
	initHostExecutableDebugInfo(modName);
	
	SymSetOptions(SYMOPT_DEFERRED_LOADS/+ | SYMOPT_UNDNAME+/);
	SymInitialize(GetCurrentProcess(), null, false);
	MODULEENTRY32 moduleEntry;
	moduleEntry.dwSize = moduleEntry.sizeof;
	
	DWORD base;
	if (0 == (base = SymLoadModule64(GetCurrentProcess(), HANDLE.init, modName.ptr, null, 0, 0))) {
		if (SysError.lastCode != 0) {
			throw new Exception("Could not SymLoadModule64: " ~ SysError.lastMsg);
		}
	}
	
	Runtime.traceHandler = &tangoTrace2Handler;
}
