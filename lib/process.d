/*
 * Copyright (c) 2005
 * Regan Heath
 *
 * Permission to use, copy, modify, distribute and sell this software
 * and its documentation for any purpose is hereby granted without fee,
 * provided that the above copyright notice appear in all copies and
 * that both that copyright notice and this permission notice appear
 * in supporting documentation.  Author makes no representations about
 * the suitability of this software for any purpose. It is provided
 * "as is" without express or implied warranty.
 */

module lib.process;
private import std.c.stdlib;
public import lib.pipestream;

extern(C) char* strdup(char*);

version(Windows) {
	public import std.c.windows.windows;
	import std.windows.syserror;

	extern(Windows) {
		struct PROCESS_INFORMATION {
		    HANDLE hProcess;
		    HANDLE hThread;
		    DWORD dwProcessId;
		    DWORD dwThreadId;
		}
		alias PROCESS_INFORMATION* PPROCESS_INFORMATION, LPPROCESS_INFORMATION;

		struct STARTUPINFOA {
		    DWORD   cb;
		    LPSTR   lpReserved;
		    LPSTR   lpDesktop;
		    LPSTR   lpTitle;
		    DWORD   dwX;
		    DWORD   dwY;
		    DWORD   dwXSize;
		    DWORD   dwYSize;
		    DWORD   dwXCountChars;
		    DWORD   dwYCountChars;
		    DWORD   dwFillAttribute;
		    DWORD   dwFlags;
		    WORD    wShowWindow;
		    WORD    cbReserved2;
		    LPBYTE  lpReserved2;
		    HANDLE  hStdInput;
		    HANDLE  hStdOutput;
		    HANDLE  hStdError;
		}
		alias STARTUPINFOA* LPSTARTUPINFOA;

		struct STARTUPINFOW {
		    DWORD   cb;
		    LPWSTR  lpReserved;
		    LPWSTR  lpDesktop;
		    LPWSTR  lpTitle;
		    DWORD   dwX;
		    DWORD   dwY;
		    DWORD   dwXSize;
		    DWORD   dwYSize;
		    DWORD   dwXCountChars;
		    DWORD   dwYCountChars;
		    DWORD   dwFillAttribute;
		    DWORD   dwFlags;
		    WORD    wShowWindow;
		    WORD    cbReserved2;
		    LPBYTE  lpReserved2;
		    HANDLE  hStdInput;
		    HANDLE  hStdOutput;
		    HANDLE  hStdError;
		}
		alias STARTUPINFOW* LPSTARTUPINFOW;

		VOID GetStartupInfoA(LPSTARTUPINFOA lpStartupInfo);
		VOID GetStartupInfoW(LPSTARTUPINFOW lpStartupInfo);

		uint STARTF_USESHOWWINDOW    = 0x00000001;
		uint STARTF_USESIZE          = 0x00000002;
		uint STARTF_USEPOSITION      = 0x00000004;
		uint STARTF_USECOUNTCHARS    = 0x00000008;
		uint STARTF_USEFILLATTRIBUTE = 0x00000010;
		uint STARTF_RUNFULLSCREEN    = 0x00000020;
		uint STARTF_FORCEONFEEDBACK  = 0x00000040;
		uint STARTF_FORCEOFFFEEDBACK = 0x00000080;
		uint STARTF_USESTDHANDLES    = 0x00000100;
		/+#if(WINVER >= 0x0400)
		#define STARTF_USEHOTKEY        0x00000200
		#endif /* WINVER >= 0x0400 */
		+/

		BOOL CreateProcessA(
		    LPCSTR lpApplicationName,
		    LPSTR lpCommandLine,
		    LPSECURITY_ATTRIBUTES lpProcessAttributes,
		    LPSECURITY_ATTRIBUTES lpThreadAttributes,
		    BOOL bInheritHandles,
		    DWORD dwCreationFlags,
		    LPVOID lpEnvironment,
		    LPCSTR lpCurrentDirectory,
		    LPSTARTUPINFOA lpStartupInfo,
		    LPPROCESS_INFORMATION lpProcessInformation
		    );

		BOOL CreateProcessW(
		    LPCWSTR lpApplicationName,
		    LPWSTR lpCommandLine,
		    LPSECURITY_ATTRIBUTES lpProcessAttributes,
		    LPSECURITY_ATTRIBUTES lpThreadAttributes,
		    BOOL bInheritHandles,
		    DWORD dwCreationFlags,
		    LPVOID lpEnvironment,
		    LPCWSTR lpCurrentDirectory,
		    LPSTARTUPINFOW lpStartupInfo,
		    LPPROCESS_INFORMATION lpProcessInformation
		    );

		//
		// dwCreationFlag values
		//

		uint DEBUG_PROCESS               = 0x00000001;
		uint DEBUG_ONLY_THIS_PROCESS     = 0x00000002;

		uint CREATE_SUSPENDED            = 0x00000004;

		uint DETACHED_PROCESS            = 0x00000008;

		uint CREATE_NEW_CONSOLE          = 0x00000010;

		uint NORMAL_PRIORITY_CLASS       = 0x00000020;
		uint IDLE_PRIORITY_CLASS         = 0x00000040;
		uint HIGH_PRIORITY_CLASS         = 0x00000080;
		uint REALTIME_PRIORITY_CLASS     = 0x00000100;

		uint CREATE_NEW_PROCESS_GROUP    = 0x00000200;
		uint CREATE_UNICODE_ENVIRONMENT  = 0x00000400;

		uint CREATE_SEPARATE_WOW_VDM     = 0x00000800;
		uint CREATE_SHARED_WOW_VDM       = 0x00001000;
		uint CREATE_FORCEDOS             = 0x00002000;

		uint CREATE_DEFAULT_ERROR_MODE   = 0x04000000;
		uint CREATE_NO_WINDOW            = 0x08000000;

		uint PROFILE_USER                = 0x10000000;
		uint PROFILE_KERNEL              = 0x20000000;
		uint PROFILE_SERVER              = 0x40000000;

		BOOL TerminateProcess(HANDLE hProcess, UINT uExitCode);
	}
}

version(linux) {
	extern (C) char* strerror(int);
}

class ProcessException : Exception
{
	version(Windows) {
		this(char[] msg) { super(msg ~ ": " ~ sysErrorString(GetLastError())); }
	}
	version(linux) {
		//for some reason getErrno does not link for me?
		this(char[] msg) { super(msg ~ ": " ~ std.string.toString(strerror(getErrno()))); }
	}
}

class Process
{
	this()
	{
	}

	this(char[] command)
	{
		this();
		execute(command);
	}

	void execute(char[] command)
	{
		if (running) kill();
		startProcess(command);
	}

	void kill()
	{
		if (!running) return;
		stopProcess(0);
	}

	void addEnv(char[] label, char[] value)
	{
		addEnv(label~"="~value);
	}

	void addEnv(char[] value)
	{
		enviroment ~= value;
	}

	char[] readLine()
	{
		return pout.readLine();
	}

	char[] readError()
	{
		return perr.readLine();
	}

	void writeLine(char[] line)
	{
		pin.writeLine(line);
	}

private:
	char[][] enviroment = null;
	bool running = false;
	PipeStream pout = null;
	PipeStream perr = null;
	PipeStream pin = null;

	version(Windows)
	{
		PROCESS_INFORMATION *info = null;

		char* makeBlock(char[][] from)
		{
			char* result = null;
			uint length = 0;
			uint upto = 0;

			foreach(char[] s; from) length += s.length; //total length of strings
			length += from.length; //add space for a \0 for each string
			length++; //add space for final terminating \0

			result = cast(char*)calloc(1,length);

			foreach(char[] s; from) {
				result[upto..upto+s.length] = s[0..s.length];
				upto += s.length+1;
			}

			return result;
		}

		void freeBlock(char* data)
		{
			free(data);
		}

		void startProcess(char[] command)
		{
			STARTUPINFOA startup;
			char* env = null;

			try {
				pout = new PipeStream();
				perr = new PipeStream();
				pin = new PipeStream();

				GetStartupInfoA(&startup);
				startup.hStdInput = pin.readHandle;
				startup.hStdOutput = pout.writeHandle;
				startup.hStdError = perr.writeHandle;
				startup.dwFlags = STARTF_USESTDHANDLES;

				info = new PROCESS_INFORMATION();
				env = makeBlock(enviroment);

				if (!CreateProcessA(null,std.string.toStringz(command),null,null,true,DETACHED_PROCESS,env,null,&startup,info)) {
					throw new ProcessException("CreateProcess");
				}

				running = true;
			} finally {
				if (env) freeBlock(env);
				if (running) {
					CloseHandle(info.hThread);
					pin.closeRead();
					pout.closeWrite();
					perr.closeWrite();
				}
				else {
					if (info) info = null;
					pout = null;
					perr = null;
					pin = null;
				}
			}
		}

		void stopProcess(uint exitCode)
		{
			if (!TerminateProcess(info.hProcess,exitCode)) {
				throw new ProcessException("TerminateProcess");
			}

			running = false;

			CloseHandle(info.hProcess);
			info = null;
			pout = null;
			perr = null;
			pin = null;
		}
	}

	version(linux)
	{
		int pid;

		char** makeBlock(char[][] from)
		{
			char** result = null;

			result = cast(char**)calloc(1,(enviroment.length+1) * typeid(char*).sizeof);
			foreach(uint i, char[] s; from)
				result[i] = strdup(toStringz(s));

			return result;
		}

		void freeBlock(char** block)
		{
			for(uint i = 0; block[i]; i++) free(block[i]);
			free(block);
		}

		char[][] splitArgs(char[] string, char[] delims)
		{
			char[] delims = " \t\r\n";
			char[][] results = null;
			bool isquot = false;
			int start = -1;

			for(int i = 0; i < string.length; i++)
			{
				if (string[i] == '\"') isquot = !isquot;
				if (isquot) continue;
				if (delims.find(string[i]) != -1) {
					if (start == -1) continue;
					results ~= string[start..i];
					start = -1;
					continue;
				}
				if (start == -1) start = i;
			}

			return results;
		}

		void startProcess(char[] command)
		{
			try {
				pin = new PipeStream();
				pout = new PipeStream();
				perr = new PipeStream();

				if (fcntl(pin.writeHandle, F_SETFD, 1) == -1) throw new ProcessException("fcntl(pin.writeHandle)");
				if (fcntl(pout.readHandle, F_SETFD, 1) == -1) throw new ProcessException("fcntl(pout.readHandle)");
				if (fcntl(perr.readHandle, F_SETFD, 1) == -1) throw new ProcessException("fcntl(perr.readHandle)");
				if (fcntl(fileno(stdin), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stdin)");
				if (fcntl(fileno(stdout), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stdout)");
				if (fcntl(fileno(stderr), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stderr)");

				pid = fork();
				if (pid == 0) {
					/* child */
					//not sure if we can even throw here?
					if (dup2(pout.writeHandle,STDOUT_FILENO) == -1) {} //throw new ProcessException("dup2(xwrite[1])");
					if (dup2(perr.writeHandle,STDERR_FILENO) == -1) {} //throw new ProcessException("dup2(xread[0])");
					if (dup2(pin.readHandle,STDIN_FILENO) == -1) {} //throw new ProcessException("dup2(xread[0])");

					pout.closeWrite();
					perr.closeWrite();
					pin.closeRead();

					/* set child uid/gid here */
					//if (setuid(uid) == -1) throw new ProcessException("setuid");
					//if (setgid(gid) == -1) throw new ProcessException("setgid");

					execve(args[0],makeBlock(splitArgs(command)),makeBlock(enviroment)); //this does not return on success
					//can we throw? how to notify parent of failure?
					exit(1);
				}
				/* parent */
				running = true;
			} finally {
				if (running) {
					pout.closeWrite();
					perr.closeWrite();
					pin.closeRead();
				}
				else {
					pin = null;
					pout = null;
					perr = null;
				}
			}
		}

		void stopProcess(uint dummy)
		{
			int r;

			if (pid == 0) return;

			if (kill(pid, SIGTERM) == -1) throw new ProcessException("kill");

			for(uint i = 0; i < 100; i++) {
				r = waitpid(pid,null,WNOHANG|WUNTRACED);
				if (r == -1) throw new ProcessException("waitpid");
				if (r == pid) break;
				usleep(50000);
			}
			running = false;
			close(output);
			close(input);
			pid = 0;
		}
	}
}

/+
void main()
{
	auto Process p = new Process("cmd /c dir");
	printf("%.*s",p.readLine());
}
+/
