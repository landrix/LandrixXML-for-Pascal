{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Leak check of the test programs: the first unit in their uses clause
  (also before cthreads), so its initialization runs before and its
  finalization after every other unit but System. It compares the heap
  at the start with the heap at the end: anything still allocated then
  (by a test, by the library, in any thread, or by a unit's finalization
  that does not free its globals) is a leak. The program then writes the
  difference to the error output and ends with exit code LeakExitCode,
  unless it already ends with another code than 0.

  Free Pascal: the live blocks, counted by a memory manager placed in
  front of the program's one (the heap status of Free Pascal is kept per
  thread; a memory manager unit such as cmem listed after this one
  replaces the counting one). Delphi 2006 and later on Windows: the bytes of FastMM's
  memory manager state; Delphi 6 and 7: GetHeapStatus. Delphi on other
  platforms: no check. Delphi 6 and 7 do not finalize the variables of
  the program itself (the .dpr): a test program clears its strings and
  dynamic arrays at its end.

  Uses System only, so no other unit is initialized before it. }

unit LandrixXmlLeakCheck;

{$I LandrixXml.inc}

interface

const
  LeakExitCode = 7;

implementation

{$IFNDEF FPC}
{$IFDEF MSWINDOWS}
{$IF CompilerVersion >= 18.0}
  {$DEFINE LANDRIXXML_MMSTATE}
{$IFEND}
  {$DEFINE LANDRIXXML_LEAKCHECK}
{ GetMemoryManagerState and GetHeapStatus are Windows symbols (W1002) }
  {$WARN SYMBOL_PLATFORM OFF}
{$ENDIF}
{$ENDIF}

{$IFDEF FPC}
var
  Previous: TMemoryManager;
  { the blocks allocated through this memory manager and not freed }
  LiveBlocks: Longint;

function CountedGetMem(Size: PtrUInt): Pointer;
begin
  Result := Previous.GetMem(Size);
  if Result <> nil then
    InterLockedIncrement(LiveBlocks);
end;

function CountedFreeMem(P: Pointer): PtrUInt;
begin
  if P <> nil then
    InterLockedDecrement(LiveBlocks);
  Result := Previous.FreeMem(P);
end;

function CountedFreeMemSize(P: Pointer; Size: PtrUInt): PtrUInt;
begin
  if P <> nil then
    InterLockedDecrement(LiveBlocks);
  Result := Previous.FreeMemSize(P, Size);
end;

function CountedAllocMem(Size: PtrUInt): Pointer;
begin
  Result := Previous.AllocMem(Size);
  if Result <> nil then
    InterLockedIncrement(LiveBlocks);
end;

function CountedReAllocMem(var P: Pointer; Size: PtrUInt): Pointer;
var
  WasNil: Boolean;
begin
  WasNil := P = nil;
  Result := Previous.ReAllocMem(P, Size);
  if WasNil and (Result <> nil) then
    InterLockedIncrement(LiveBlocks)
  else if not WasNil and (P = nil) then
    { freed (size 0); a failed grow keeps P }
    InterLockedDecrement(LiveBlocks);
end;

procedure StartCheck;
var
  Counted: TMemoryManager;
begin
  GetMemoryManager(Previous);
  Counted := Previous;
  Counted.GetMem := @CountedGetMem;
  Counted.FreeMem := @CountedFreeMem;
  Counted.FreeMemSize := @CountedFreeMemSize;
  Counted.AllocMem := @CountedAllocMem;
  Counted.ReAllocMem := @CountedReAllocMem;
  SetMemoryManager(Counted);
end;

procedure EndCheck;
var
  Left: Longint;
begin
  Left := LiveBlocks;
  SetMemoryManager(Previous);
  if Left > 0 then
  begin
    WriteLn(StdErr, 'leak check: ', Left, ' blocks still allocated at the end');
    { not written otherwise when the error output is a pipe }
    Flush(StdErr);
    if ExitCode = 0 then
      ExitCode := LeakExitCode;
  end;
end;
{$ELSE}
{$IFDEF LANDRIXXML_LEAKCHECK}
var
  AtStart: Int64;

function HeapInUse: Int64;
{$IFDEF LANDRIXXML_MMSTATE}
var
  State: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(State);
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Result := Result + Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount) *
      State.SmallBlockTypeStates[I].UseableBlockSize;
end;
{$ELSE}
begin
  Result := GetHeapStatus.TotalAllocated;
end;
{$ENDIF}

procedure StartCheck;
begin
  AtStart := HeapInUse;
end;

procedure EndCheck;
var
  Left: Int64;
begin
  Left := HeapInUse - AtStart;
  if Left > 0 then
  begin
    WriteLn(ErrOutput, 'leak check: ', Left, ' bytes still allocated at the end');
    if ExitCode = 0 then
      ExitCode := LeakExitCode;
  end;
end;
{$ELSE}
procedure StartCheck;
begin
end;

procedure EndCheck;
begin
end;
{$ENDIF}
{$ENDIF}

initialization
  StartCheck;

finalization
  EndCheck;
end.
