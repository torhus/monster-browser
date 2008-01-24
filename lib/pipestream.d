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

module lib.pipestream;
private import std.stream;

extern(C) char* strdup(char*);

version(Windows) {
	import std.c.windows.windows;
	import std.windows.syserror;

	extern(Windows) {
		alias HANDLE* PHANDLE;

		BOOL CreatePipe(
		    PHANDLE hReadPipe,
		    PHANDLE hWritePipe,
		    LPSECURITY_ATTRIBUTES lpPipeAttributes,
		    DWORD nSize
		    );

		BOOL PeekNamedPipe(
		    HANDLE hNamedPipe,
		    LPVOID lpBuffer,
		    DWORD nBufferSize,
		    LPDWORD lpBytesRead,
		    LPDWORD lpTotalBytesAvail,
		    LPDWORD lpBytesLeftThisMessage
		    );
	}
}

version(linux) {
	private import std.c.stdlib;
	extern (C) char* strerror(int);
}

version(Windows)
{
	class PipeException : Exception
	{
		this(char[] msg) { super(msg ~ ": " ~ sysErrorString(GetLastError())); }
	}

	class PipeStream : Stream
	{
		this(uint bufferSize = 0)
		{
			SECURITY_ATTRIBUTES security;

			security.nLength = security.sizeof;
			security.lpSecurityDescriptor = null;
			security.bInheritHandle = true;

			if (!CreatePipe(&read,&write,&security,bufferSize))
				throw new PipeException("CreatePipe");

			writeable = true;
			readable = true;
			seekable = false;
			isopen = true;
		}

		HANDLE readHandle()
		{
			return read;
		}

		HANDLE writeHandle()
		{
			return write;
		}

		void closeRead()
		{
			CloseHandle(readHandle);
			read = INVALID_HANDLE_VALUE;
			readable = false;
			if (!writeable) isopen = false;
		}

		void closeWrite()
		{
			CloseHandle(writeHandle);
			write = INVALID_HANDLE_VALUE;
			writeable = false;
			if (!readable) isopen = false;
		}

		override void close()
		{
			closeRead();
			closeWrite();
		}

		override ulong seek(long offset, SeekPos whence)
		{
			assertSeekable();
			return 0;
		}


		override size_t readBlock(void* buffer, size_t size)
		{
			size_t bytes = 0;
			assertReadable();
			if (!ReadFile(readHandle,buffer,size,&bytes,null)) throw new PipeException("ReadFile");
			return bytes;
		}

		override size_t available()
		{
			size_t bytes = 0;
			assertReadable();
			if (!PeekNamedPipe(readHandle,null,0,null,&bytes,null)) throw new PipeException("PeekNamedPipe");
			return bytes;
		}

		override size_t writeBlock(void* buffer, size_t size)
		{
			size_t bytes = 0;
			assertWriteable();
			if (!WriteFile(writeHandle,buffer,size,&bytes,null)) throw new PipeException("WriteFile");
			return bytes;
		}

		override void flush()
		{
			assertWriteable();
			FlushFileBuffers(writeHandle);
		}

	private:
		HANDLE write = INVALID_HANDLE_VALUE;
		HANDLE read = INVALID_HANDLE_VALUE;
	}
}

version(linux)
{
	class PipeException : Exception
	{
		//for some reason getErrno does not link for me?
		this(char[] msg) { super(msg ~ ": " ~ std.string.toString(strerror(getErrno()))); }
	}

	class PipeStream : Stream
	{
		this(uint dummy = 0)
		{
			/*if (pipe(handle) == -1) throw new PipeException("pipe(handle)");
			writeable = true;
			readable = true;
			seekable = false;
			isopen = true;*/
		}

		int readHandle()
		{
			return handle[0];
		}

		int writeHandle()
		{
			return handle[1];
		}

		void closeRead()
		{
			/*close(readHandle);
			readable = false;
			if (!writeable) isopen = false;*/
		}

		void closeWrite()
		{
			/*close(writeHandle);
			writeable = false;
			if (!readable) isopen = false;*/
		}

		override void close()
		{
			closeRead();
			closeWrite();
		}

		override ulong seek(long offset, SeekPos whence)
		{
			assertSeekable();
			return 0;
		}

		override size_t readBlock(void* buffer, size_t size)
		{
			/*size_t bytes;
			assertReadable();
			bytes = read(readHandle,buffer,size);
			if (bytes == -1) throw new PipeException("read(handle[0])");
			return bytes;*/
			return 0;
		}

		override size_t available()
		{
			/*size_t bytes;
			assertReadable();
			if (ioctl(readHandle,FIONREAD,&bytes) == -1) throw new PipeException("ioctl(handle[0])");
			return bytes;*/
			return 0;
		}

		override size_t writeBlock(void* buffer, size_t size)
		{
			/*size_t bytes;
			assertWriteable();
			bytes = write(writeHandle,buffer,size);
			if (bytes == -1) throw new PipeException("write(handle[1])");
			return bytes;*/
			return 0;
		}

		override void flush()
		{
			assertWriteable();
			//writeHandle
		}

	private:
		int handle[2];
	}
}

/+
class Process : Stream
{
	alias std.stdio.writefln debugf;

	this()
	{
		super();
		seekable = false;
		readable = true;
		writeable = true;
		isopen = false;
	}

	this(char[] command)
	{
		this();
		open(command);
	}

	~this()
	{
		close();
	}

	void addEnv(char[] label, char[] value)
	{
		addEnv(label~"="~value);
	}

	void addEnv(char[] value)
	{
		enviroment ~= value;
	}

	void open(char[] command)
	{
		if (isopen) close();
		startProcess(command);
	}

	override void close()
	{
		if (!isopen) return ;
		flush();
		stopProcess(0);
		isopen = false;
	}

	override ulong seek(long offset, SeekPos whence)
	{
		assertSeekable();
	}

	version(Windows)
	{
		override size_t readBlock(void* buffer, size_t size)
		{
			size_t bytes = 0;
			if (!isopen) return 0;
			if (!ReadFile(output,buffer,size,&bytes,null)) throw new ProcessException("ReadFile");
			return bytes;
		}

		override size_t writeBlock(void* buffer, size_t size)
		{
			size_t bytes = 0;
			if (!isopen) return 0;
			if (!WriteFile(input,buffer,size,&bytes,null)) throw new ProcessException("WriteFile");
			return bytes;
		}

		override size_t available()
		{
			size_t bytes = 0;
			if (!isopen) return 0;
			if (!PeekNamedPipe(output,null,0,null,&bytes,null)) throw new ProcessException("PeekNamedPipe");
			return bytes;
		}

		override void flush()
		{
			if (!isopen) return ;
			FlushFileBuffers(output);
		}
	}

	version(linux)
	{
		override size_t readBlock(void* buffer, size_t size)
		{
			size_t bytes;

			bytes = read(output,buffer,size);
			if (bytes == -1) throw new ProcessException("read");
			return bytes;
		}

		override size_t writeBlock(void* buffer, size_t size)
		{
			size_t bytes;

			bytes = write(output,buffer,size);
			if (bytes == -1) throw new ProcessException("write");
			return bytes;
		}

		override size_t available()
		{
			size_t bytes;

			if (ioctl(output,FIONREAD,&bytes) == -1) throw new ProcessException("ioctl");
			return bytes;
		}
	}

private:
	char[][] enviroment = null;

	version(Windows)
	{
		HANDLE output = INVALID_HANDLE_VALUE;
		HANDLE input = INVALID_HANDLE_VALUE;
		PROCESS_INFORMATION* info = null;
		int bufferSize = 0;

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
			HANDLE read1,read2,read3,write1,write2,write3;
			SECURITY_ATTRIBUTES security;
			STARTUPINFOA startup;
			char* env;

			read1 = read2 = read3 = write1 = write2 = write2 = INVALID_HANDLE_VALUE;

			security.nLength = security.sizeof;
			security.lpSecurityDescriptor = null;
			security.bInheritHandle = true;

			env = null;

			try {
				if (!CreatePipe(&read1,&write1,&security,bufferSize)) throw new ProcessException("CreatePipe");
				if (!CreatePipe(&read2,&write2,&security,bufferSize)) throw new ProcessException("CreatePipe");
				if (!CreatePipe(&read3,&write3,&security,bufferSize)) throw new ProcessException("CreatePipe");

				GetStartupInfoA(&startup);
				startup.hStdInput = read1;
				startup.hStdOutput = write2;
				startup.hStdError = write3;
				startup.dwFlags = STARTF_USESTDHANDLES;

				info = new PROCESS_INFORMATION();
				env = makeBlock(enviroment);

				if (!CreateProcessA(null,toStringz(command),null,null,true,DETACHED_PROCESS,env,null,&startup,info))
					throw new ProcessException("CreateProcess");

				input = write1;
				output = read2;
				isopen = true;

			}
			finally {
				if (!isopen && read2 != INVALID_HANDLE_VALUE) CloseHandle(read2);
				if (!isopen && write1 != INVALID_HANDLE_VALUE) CloseHandle(write1);
				if (read1 != INVALID_HANDLE_VALUE) CloseHandle(read1);
				if (read3 != INVALID_HANDLE_VALUE) CloseHandle(read3);
				if (write2 != INVALID_HANDLE_VALUE) CloseHandle(write2);
				if (write3 != INVALID_HANDLE_VALUE) CloseHandle(write3);
				if (info) CloseHandle(info.hThread);
				if (env) freeBlock(env);
			}
		}

		void stopProcess(uint exitCode)
		{
			if (!TerminateProcess(info.hProcess,exitCode)) throw new ProcessException("TerminateProcess");
			isopen = false;

			CloseHandle(info.hProcess);
			delete info;
			info = null;

			CloseHandle(output);
			output = INVALID_HANDLE_VALUE;

			CloseHandle(input);
			input = INVALID_HANDLE_VALUE;
		}
	}

	version(linux)
	{
		int output = 0;
		int input = 0;
		int pid = 0;

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
			int xwrite[2];
			int xread[2];

			try {
				if (pipe(xwrite) == -1) throw new ProcessException("pipe(xwrite)");
				if (pipe(xread) == -1) throw new ProcessException("pipe(xread)");

				if (fcntl(input, F_SETFD, 1) == -1) throw new ProcessException("fcntl(input)");
				if (fcntl(output, F_SETFD, 1) == -1) throw new ProcessException("fcntl(output)");
				if (fcntl(fileno(stdin), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stdin)");
				if (fcntl(fileno(stdout), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stdout)");
				if (fcntl(fileno(stderr), F_SETFD, 1) == -1) throw new ProcessException("fcntl(stderr)");

				pid = fork();
				if (pid == 0) {
					/* child */
					char** args = null;
					char** env = null;

					//not sure if we can even throw here?
					if (dup2(xwrite[1],STDOUT_FILENO) == -1) {} //throw new ProcessException("dup2(xwrite[1])");
					if (dup2(xread[0], STDIN_FILENO) == -1) {} //throw new ProcessException("dup2(xread[0])");

					close(xwrite[1]);
					close(xread[0]);

					/* set child uid/gid here */
					//if (setuid(uid) == -1) throw new ProcessException("setuid");
					//if (setgid(gid) == -1) throw new ProcessException("setgid");

					args = makeBlock(splitArgs(command));
					env = makeBlock(enviroment);
					execve(args[0],args,env); //this does not return on success
					//can we throw? how to notify parent of failure?
					exit(1);
				}
				/* parent */
				isopen = true;
			} finally {
				close(xwrite[1]);
				close(xread[0]);
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
			isopen = false;
			close(output);
			close(input);
			pid = 0;
		}
	}
}
+/
