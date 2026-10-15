{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Conformance helper: reads every file named in a list file (one path per
  line) with TLandrixXmlReader and prints one result line per file:
    <path> TAB OK
    <path> TAB ERR TAB <code> TAB <line> TAB <column> TAB <message>
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
  LandrixXmlReader;

var
  List: TStringList;
  Reader: TLandrixXmlReader;
  I: Integer;
  Path: string;

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
    List.LoadFromFile(ParamStr(1));
    for I := 0 to List.Count - 1 do
    begin
      Path := Trim(List[I]);
      if Path = '' then
        Continue;
      try
        Reader.LoadFromFile(Path);
        while Reader.Read do
          ;
        WriteLn(Path, #9, 'OK');
      except
        on E: ELandrixXmlError do
          WriteLn(Path, #9, 'ERR', #9, Ord(E.Code), #9, E.Line, #9, E.Column, #9, E.Message);
        on E: Exception do
          WriteLn(Path, #9, 'EXC', #9, E.ClassName, #9, E.Message);
      end;
    end;
  finally
    Reader.Free;
    List.Free;
  end;
end.
