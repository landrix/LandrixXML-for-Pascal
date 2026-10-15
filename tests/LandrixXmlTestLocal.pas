{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Real-world files from the git-ignored folder tests/data/local
  (xrechnung, zugferd, gaeb). Skipped silently when the folder is missing.
  Every file is classified:
    accepted -> load into the DOM, save, reload: the token stream must be
                identical to the original (also after the writer copy);
    rejected -> must be an ELandrixXmlError with a position; allowed only
                for GAEB files (they may be malformed), an error for
                XRechnung/ZUGFeRD files.
  In addition, damaged copies of every file (truncated, single bytes
  replaced) must load or be rejected cleanly.
  Only file names and positions are printed, never contents. The
  cross-check with an independent parser is tools/check-local.py. }

unit LandrixXmlTestLocal;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlDom,
  LandrixXmlTestFramework;

function LocalRoot: string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'local' + PathDelim;
end;

procedure CollectFiles(const Dir: string; List: TStringList);
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        CollectFiles(Dir + SR.Name + PathDelim, List)
      else
        List.Add(Dir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function TokenKey(Reader: TLandrixXmlReader): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(Ord(Reader.TokenType))) + '|' + Reader.NameUtf8 +
    '|' + Reader.NamespaceUriUtf8 + '|' + Reader.ValueUtf8;
  if Reader.TokenType = xttStartElement then
    for I := 0 to Reader.AttributeCount - 1 do
      Result := Result + '|' + Reader.AttributeNameUtf8(I) + '{' +
        Reader.AttributeNamespaceUriUtf8(I) + '}=' + Reader.AttributeValueUtf8(I);
  Result := Result + #10;
end;

function Tokens(Reader: TLandrixXmlReader): TLandrixXmlUtf8;
var
  Buf: TLandrixXmlBuffer;
begin
  Buf := TLandrixXmlBuffer.Create;
  try
    while Reader.Read do
      Buf.AppendUtf8(TokenKey(Reader));
    Result := Buf.AsUtf8;
  finally
    Buf.Free;
  end;
end;

procedure CheckFile(const FileName, Folder: string; var Accepted, Rejected: Integer);
var
  Reader: TLandrixXmlReader;
  Doc: TLandrixXmlDocument;
  Original: TLandrixXmlUtf8;
  Name: string;
begin
  Name := Folder + PathDelim + ExtractFileName(FileName);
  Reader := TLandrixXmlReader.Create;
  Doc := TLandrixXmlDocument.Create;
  try
    try
      Reader.LoadFromFile(FileName);
      Original := Tokens(Reader);
    except
      on E: ELandrixXmlError do
      begin
        Inc(Rejected);
        WriteLn('  rejected ', Name, ': code ', Ord(E.Code), ', line ', E.Line, ', column ',
          E.Column);
        Check(E.Line > 0, Name + ': rejection without a position');
        Check(Folder = 'gaeb', Name + ': e-invoice files must be well-formed');
        Exit;
      end;
    end;
    Inc(Accepted);
    Doc.LoadFromFile(FileName);
    Reader.LoadFromUtf8(Doc.SaveToUtf8);
    Check(Tokens(Reader) = Original, Name + ': DOM round trip changed the tokens');
    { the dropping option must load every file as well }
    Doc.WhitespaceMode := xwmDropBetweenElements;
    Doc.LoadFromFile(FileName);
    Check(Doc.Root <> nil, Name + ': root element with whitespace dropping');
  finally
    Doc.Free;
    Reader.Free;
  end;
end;

{ Damaged copies (truncated, single bytes replaced) must either load or be
  rejected with ELandrixXmlError and a position - never another exception. }
procedure CheckDamaged(const FileName, Folder: string);
const
  Replacements: array[0..3] of Byte = (Ord('<'), Ord('&'), 0, 255);
var
  F: TFileStream;
  Data, Damaged: AnsiString;
  Reader: TLandrixXmlReader;
  K: Integer;
  Name: string;

  procedure Probe(const Bytes: AnsiString; const What: string);
  begin
    try
      Reader.LoadFromBuffer(PAnsiChar(Bytes)^, Length(Bytes));
      while Reader.Read do
        ;
    except
      on E: ELandrixXmlError do
        Check(E.Offset >= 0, Name + ' ' + What + ': rejection without a position');
      on E: Exception do
        Fail(Name + ' ' + What + ': ' + E.ClassName + ' instead of ELandrixXmlError');
    end;
  end;

begin
  Name := Folder + PathDelim + ExtractFileName(FileName);
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := '';
    SetLength(Data, Integer(F.Size));
    if Length(Data) > 0 then
      F.ReadBuffer(PAnsiChar(Data)^, Length(Data));
  finally
    F.Free;
  end;
  if Length(Data) < 16 then
    Exit;
  Reader := TLandrixXmlReader.Create;
  try
    for K := 1 to 4 do
      Probe(Copy(Data, 1, Length(Data) * K div 5), 'truncated');
    for K := 0 to 3 do
    begin
      Damaged := Data;
      UniqueString(Damaged);
      Damaged[1 + Length(Data) * (K + 1) div 6] := AnsiChar(Replacements[K]);
      Probe(Damaged, 'damaged');
    end;
  finally
    Reader.Free;
  end;
end;

procedure TestLocalFiles;
const
  Folders: array[0..2] of string = ('xrechnung', 'zugferd', 'gaeb');
var
  List: TStringList;
  F, I, Accepted, Rejected: Integer;
begin
  for F := 0 to High(Folders) do
  begin
    if not DirectoryExists(LocalRoot + Folders[F]) then
      Continue;
    List := TStringList.Create;
    try
      CollectFiles(LocalRoot + Folders[F] + PathDelim, List);
      List.Sort;
      Accepted := 0;
      Rejected := 0;
      for I := 0 to List.Count - 1 do
      begin
        CheckFile(List[I], Folders[F], Accepted, Rejected);
        CheckDamaged(List[I], Folders[F]);
      end;
      if List.Count > 0 then
        WriteLn('  local ', Folders[F], ': ', Accepted, ' accepted, ', Rejected, ' rejected');
    finally
      List.Free;
    end;
  end;
end;

procedure Register;
begin
  RegisterTest('Local.RealWorldFiles', TestLocalFiles);
end;

end.
