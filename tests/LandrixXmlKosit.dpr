{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Helper of tools/run-kosit-suite.py (the KoSIT XRechnung test suite):
  validates each document of a job file with an XML schema and rule files
  and writes the results; the driver compares them with KoSIT and Saxon.
  Usage: LandrixXmlKosit <job-file> <result-file>

  Job file (UTF-8, one item per line):
    doc NAME           starts a document; NAME is only echoed
    file FILE          the document to validate
    xsd FILE           the XML schema (loaded once per file name)
    rules NAME FILE    a rule file, its results under NAME (loaded once)
    run
  Result file, per document:
    ## NAME
    xsd valid | xsd invalid
    xsd-error CODE LINE:COLUMN      per schema error, in order
    ### NAME                        per rule file
    fired CONTEXT                   per fired rule, in order
    KIND ID FLAG LOCATION | MESSAGE per failed assert or successful report
    dynamic-error CODE | MESSAGE    per dynamic error
    exception CLASS MESSAGE         reading or validating raised it
  Every line is written at once, so a crash leaves the documents before it
  complete. }

program LandrixXmlKosit;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXsdSchema,
  LandrixXmlXsdSchemaLoader,
  LandrixXmlXsdValidator,
  LandrixXmlSchematron;

var
  Output: TFileStream;
  { file names and the loaded schema sets and rule files }
  Schemas: TStringList;
  RuleFiles: TStringList;

procedure Put(const Line: TLandrixXmlUtf8);
var
  S: TLandrixXmlUtf8;
begin
  S := Line + #10;
  Output.WriteBuffer(PAnsiChar(S)^, Length(S));
end;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ the lines of the file, without empty ones and line ends }
function FileLines(const FileName: string): TLandrixXmlUtf8Array;
var
  F: TFileStream;
  Data: TLandrixXmlUtf8;
  I, Start, N: Integer;
begin
  Result := nil;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := '';
    SetLength(Data, Integer(F.Size));
    if Length(Data) > 0 then
      F.ReadBuffer(PAnsiChar(Data)^, Length(Data));
  finally
    F.Free;
  end;
  N := 0;
  Start := 1;
  for I := 1 to Length(Data) + 1 do
    if (I > Length(Data)) or (Data[I] = #10) or (Data[I] = #13) then
    begin
      if I > Start then
      begin
        if N = Length(Result) then
          SetLength(Result, 2 * N + 64);
        Result[N] := Copy(Data, Start, I - Start);
        Inc(N);
      end;
      Start := I + 1;
    end;
  SetLength(Result, N);
end;

{ the text before the first space (Head) and after it (the result) }
function Split(const S: TLandrixXmlUtf8; out Head: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  P: Integer;
begin
  P := 1;
  while (P <= Length(S)) and (S[P] <> ' ') do
    Inc(P);
  Head := Copy(S, 1, P - 1);
  Result := Copy(S, P + 1, MaxInt);
end;

function SchemaOf(const FileName: string): TLandrixXmlXsdSchemaSet;
var
  I: Integer;
begin
  I := Schemas.IndexOf(FileName);
  if I < 0 then
    I := Schemas.AddObject(FileName, LandrixXmlXsdLoadSchema(FileName));
  Result := TLandrixXmlXsdSchemaSet(Schemas.Objects[I]);
end;

function RulesOf(const FileName: string): TLandrixXmlSchematronRules;
var
  I: Integer;
  Rules: TLandrixXmlSchematronRules;
begin
  I := RuleFiles.IndexOf(FileName);
  if I < 0 then
  begin
    Rules := TLandrixXmlSchematronRules.Create;
    try
      Rules.LoadFromFile(FileName);
    except
      Rules.Free;
      raise;
    end;
    I := RuleFiles.AddObject(FileName, Rules);
  end;
  Result := TLandrixXmlSchematronRules(RuleFiles.Objects[I]);
end;

{ the byte position of the first TAB in S, 0 if there is none }
function TabPos(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] = #9 then
    begin
      Result := I;
      Exit;
    end;
end;

procedure PutException(E: Exception);
begin
  Put(U('exception ' + E.ClassName + ' ' + StringReplace(E.Message, #10, ' ', [rfReplaceAll])));
end;

procedure CheckSchema(const Document, Schema: string);
var
  V: TLandrixXmlXsdValidator;
  I: Integer;
  E: TLandrixXmlXsdValidationError;
begin
  V := TLandrixXmlXsdValidator.Create(SchemaOf(Schema));
  try
    V.MaxErrors := 0;
    if V.ValidateFile(Document) then
      Put(U('xsd valid'))
    else
      Put(U('xsd invalid'));
    for I := 0 to V.ErrorCount - 1 do
    begin
      E := V.Errors[I];
      Put(U('xsd-error ' + E.Code + ' ' + IntToStr(E.Line) + ':' + IntToStr(E.Column)));
    end;
  finally
    V.Free;
  end;
end;

const
  KindText: array[TLandrixXmlSchematronResultKind] of string = ('failed-assert', 'successful-report',
    'dynamic-error');

procedure CheckRules(const Document, RulesFile: string);
var
  V: TLandrixXmlSchematronValidator;
  I, P: Integer;
  R: TLandrixXmlSchematronResult;
  S: TLandrixXmlUtf8;
begin
  V := TLandrixXmlSchematronValidator.Create(RulesOf(RulesFile));
  try
    V.RecordFiredRules := True;
    V.ValidateFile(Document);
    for I := 0 to V.FiredRules.Count - 1 do
    begin
      S := U(V.FiredRules[I]);
      { pattern TAB context TAB location: the context }
      P := TabPos(S);
      S := Copy(S, P + 1, MaxInt);
      P := TabPos(S);
      Put(U('fired ') + Copy(S, 1, P - 1));
    end;
    for I := 0 to V.ResultCount - 1 do
    begin
      R := V.Results[I];
      if R.Kind = xsrDynamicError then
        Put(U('dynamic-error ' + R.ErrorCode + ' | ') + R.Message)
      else
        Put(U(KindText[R.Kind] + ' ') + R.Id + ' ' + R.Flag + ' ' + R.Location + ' | ' + R.Message);
    end;
  finally
    V.Free;
  end;
end;

procedure Run(const Name: TLandrixXmlUtf8; const Document, Schema: string; RuleNames: TLandrixXmlUtf8Array;
  Rules: TStringList);
var
  I: Integer;
begin
  Put(U('## ') + Name);
  if Schema <> '' then
    try
      CheckSchema(Document, Schema);
    except
      on E: Exception do
        PutException(E);
    end;
  for I := 0 to Rules.Count - 1 do
  begin
    Put(U('### ') + RuleNames[I]);
    try
      CheckRules(Document, Rules[I]);
    except
      on E: Exception do
        PutException(E);
    end;
  end;
end;

procedure FreeObjects(List: TStringList);
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    List.Objects[I].Free;
  List.Free;
end;

var
  Lines, RuleNames: TLandrixXmlUtf8Array;
  Rules: TStringList;
  Name, Head, Rest, RuleName: TLandrixXmlUtf8;
  Document, Schema: string;
  I: Integer;

begin
  Lines := nil;
  RuleNames := nil;
  if ParamCount <> 2 then
  begin
    WriteLn('Usage: LandrixXmlKosit <job-file> <result-file>');
    ExitCode := 2;
    Exit;
  end;
  Lines := FileLines(ParamStr(1));
  Output := TFileStream.Create(ParamStr(2), fmCreate);
  Schemas := TStringList.Create;
  RuleFiles := TStringList.Create;
  Rules := TStringList.Create;
  try
    Name := '';
    Document := '';
    Schema := '';
    for I := 0 to Integer(Length(Lines)) - 1 do
    begin
      Rest := Split(Lines[I], Head);
      if Head = 'doc' then
      begin
        Name := Rest;
        Document := '';
        Schema := '';
        Rules.Clear;
        RuleNames := nil;
      end
      else if Head = 'file' then
        Document := LandrixXmlUtf8ToString(Rest)
      else if Head = 'xsd' then
        Schema := LandrixXmlUtf8ToString(Rest)
      else if Head = 'rules' then
      begin
        Rest := Split(Rest, RuleName);
        SetLength(RuleNames, Length(RuleNames) + 1);
        RuleNames[High(RuleNames)] := RuleName;
        Rules.Add(LandrixXmlUtf8ToString(Rest));
      end
      else if Head = 'run' then
        Run(Name, Document, Schema, RuleNames, Rules);
    end;
  finally
    Rules.Free;
    FreeObjects(RuleFiles);
    FreeObjects(Schemas);
    Output.Free;
  end;
end.
