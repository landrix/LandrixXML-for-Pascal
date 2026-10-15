{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Conformance helper: reads every file named in a list file (UTF-8, one
  path per line) with TLandrixXmlReader and prints one result line per file,
  identified by its 0-based line number in the list (paths may contain
  characters the console cannot show):
    <index> TAB OK
    <index> TAB ERR TAB <code> TAB <line> TAB <column> TAB <message>
    <index> TAB RTFAIL TAB <message>
  For every accepted document it also copies the token stream through
  TLandrixXmlWriter and loads, saves and reloads it with TLandrixXmlDocument;
  RTFAIL means a token stream differs from the original (a writer or DOM
  defect).
  Used by tools/run-xmlconf.py with the W3C XML conformance test suite.

  Usage: LandrixXmlConformance <list-file> }

program LandrixXmlConformance;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlReader,
  LandrixXmlWriter,
  LandrixXmlDom;

{ Canonical form of the current token. Emptiness (<a/> vs <a></a>) is not
  part of it: the writer always writes <a/> for empty elements. }
function TokenKey(Reader: TLandrixXmlReader): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(Ord(Reader.TokenType))) + '|' +
    Reader.NameUtf8 + '|' + Reader.NamespaceUriUtf8 + '|' + Reader.ValueUtf8;
  if Reader.TokenType = xttStartElement then
    for I := 0 to Reader.AttributeCount - 1 do
      Result := Result + '|' + Reader.AttributeNameUtf8(I) + '{' +
        Reader.AttributeNamespaceUriUtf8(I) + '}=' + Reader.AttributeValueUtf8(I);
  Result := Result + #10;
end;

{ Copies the document to Writer; returns the token keys of the input. }
function CopyDocument(Reader: TLandrixXmlReader; Writer: TLandrixXmlWriter): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  while Reader.Read do
  begin
    Result := Result + TokenKey(Reader);
    case Reader.TokenType of
      xttStartElement:
        begin
          Writer.StartElement(Reader.NameUtf8);
          for I := 0 to Reader.AttributeCount - 1 do
            Writer.AttributeUtf8(Reader.AttributeNameUtf8(I), Reader.AttributeValueUtf8(I));
        end;
      xttEndElement:
        Writer.EndElement;
      xttText:
        Writer.TextUtf8(Reader.ValueUtf8);
      xttCData:
        Writer.CDataUtf8(Reader.ValueUtf8);
      xttComment:
        Writer.CommentUtf8(Reader.ValueUtf8);
      xttProcessingInstruction:
        Writer.ProcessingInstructionUtf8(Reader.NameUtf8, Reader.ValueUtf8);
      xttDocumentType:
        Writer.DocumentType(Reader.NameUtf8, Reader.ValueUtf8);
    else
      ;
    end;
  end;
  Writer.EndDocument;
end;

function Tokens(Reader: TLandrixXmlReader): TLandrixXmlUtf8;
begin
  Result := '';
  while Reader.Read do
    Result := Result + TokenKey(Reader);
end;

function RoundTrip(const Path: string; Reader: TLandrixXmlReader): string;
var
  Writer: TLandrixXmlWriter;
  Doc: TLandrixXmlDocument;
  First, Second: TLandrixXmlUtf8;
begin
  Result := '';
  Writer := TLandrixXmlWriter.Create;
  try
    try
      Reader.LoadFromFile(Path);
      First := CopyDocument(Reader, Writer);
    except
      on E: Exception do
      begin
        Result := 'writing failed: ' + E.ClassName + ': ' + E.Message;
        Exit;
      end;
    end;
    try
      Reader.LoadFromUtf8(Writer.AsUtf8);
      Second := Tokens(Reader);
    except
      on E: Exception do
      begin
        Result := 'output not well-formed: ' + E.Message;
        Exit;
      end;
    end;
    if First <> Second then
      Result := 'token streams differ';
  finally
    Writer.Free;
  end;
  if Result <> '' then
    Exit;
  Doc := TLandrixXmlDocument.Create;
  try
    try
      Doc.LoadFromFile(Path);
      Reader.LoadFromUtf8(Doc.SaveToUtf8);
      Second := Tokens(Reader);
    except
      on E: Exception do
      begin
        Result := 'DOM round trip failed: ' + E.ClassName + ': ' + E.Message;
        Exit;
      end;
    end;
    if First <> Second then
      Result := 'DOM token streams differ';
  finally
    Doc.Free;
  end;
end;

{ Lines of a UTF-8 text file, converted to native strings. }
procedure ReadList(const FileName: string; List: TStringList);
var
  F: TFileStream;
  Data, Line: TLandrixXmlUtf8;
  I, Start, Len: Integer;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := '';
    SetLength(Data, Integer(F.Size));
    if Length(Data) > 0 then
      F.ReadBuffer(PAnsiChar(Data)^, Length(Data));
  finally
    F.Free;
  end;
  Start := 1;
  { skip a UTF-8 byte order mark }
  if (Length(Data) >= 3) and (Ord(Data[1]) = $EF) and (Ord(Data[2]) = $BB) and (Ord(Data[3]) = $BF) then
    Start := 4;
  for I := Start to Length(Data) + 1 do
    if (I > Length(Data)) or (Data[I] = #10) then
    begin
      Len := I - Start;
      if (Len > 0) and (Data[Start + Len - 1] = #13) then
        Dec(Len);
      Line := '';
      if Len > 0 then
      begin
        SetLength(Line, Len);
        Move(PAnsiChar(Data)[Start - 1], PAnsiChar(Line)^, Len);
      end;
      List.Add(LandrixXmlUtf8ToString(Line));
      Start := I + 1;
    end;
end;

var
  List: TStringList;
  Reader: TLandrixXmlReader;
  I: Integer;
  Path, Msg: string;
  Ok: Boolean;

begin
  if ParamCount < 1 then
  begin
    WriteLn('Usage: LandrixXmlConformance <list-file>');
    ExitCode := 2;
    Exit;
  end;
  List := TStringList.Create;
  Reader := TLandrixXmlReader.Create;
  try
    ReadList(ParamStr(1), List);
    for I := 0 to List.Count - 1 do
    begin
      Path := Trim(List[I]);
      if Path = '' then
        Continue;
      Ok := False;
      try
        Reader.LoadFromFile(Path);
        while Reader.Read do
          ;
        Ok := True;
      except
        on E: ELandrixXmlError do
          WriteLn(I, #9, 'ERR', #9, Ord(E.Code), #9, E.Line, #9, E.Column, #9, E.Message);
        on E: Exception do
          WriteLn(I, #9, 'EXC', #9, E.ClassName, #9, E.Message);
      end;
      if Ok then
      begin
        Msg := RoundTrip(Path, Reader);
        if Msg = '' then
          WriteLn(I, #9, 'OK')
        else
          WriteLn(I, #9, 'RTFAIL', #9, Msg);
      end;
    end;
  finally
    Reader.Free;
    List.Free;
  end;
end.
