{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Helper of tools/run-xsts.py (the W3C XML Schema Test Suite): loads the
  schemas of a job file, validates the instance documents against them
  and writes the outcomes; the driver compares them with the expected
  validity. Usage: LandrixXmlXsts <job-file> <result-file> [first-group]

  Job file (one item per line, fields separated by a tab):
    group NAME
    schema FILE        the entry schema document
    ns URI FILE        an import of URI reads FILE (further schema documents)
    load               loads the schema
    instance NAME FILE validates FILE against the loaded schema
    end
  Result file (fields separated by a tab): "group NAME", then "schema ok",
  "schema error CODE MESSAGE" (ELandrixXmlError: CODE schema,
  unsupported, unicode, encoding, syntax, namespace, char, limit or the
  number of another error code) or "schema exception CLASS MESSAGE";
  per instance "instance NAME valid", "instance NAME invalid CODE
  MESSAGE" (the first validation error; CODE as Xerces, or
  "unsupported"), "instance NAME error CODE MESSAGE" or "instance NAME
  exception CLASS MESSAGE"; "done" after the group. Instances of a group
  whose schema did not load are not run. Every line is written at once,
  so a crash leaves the groups before it complete. The job file is read
  in the system code page: the driver writes ASCII paths only. }

program LandrixXmlXsts;

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
  LandrixXmlXsdValidator;

var
  Output: TFileStream;

procedure Put(const Line: string);
var
  S: TLandrixXmlUtf8;
begin
  S := LandrixXmlStringToUtf8(Line) + #10;
  Output.WriteBuffer(PAnsiChar(S)^, Length(S));
end;

{ a message on one line: control characters become spaces }
function OneLine(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Ord(Result[I]) < 32 then
      Result[I] := ' ';
end;

function CodeName(Code: TLandrixXmlErrorCode): string;
begin
  case Code of
    xecSchema: Result := 'schema';
    xecUnsupported: Result := 'unsupported';
    xecInvalidUnicode: Result := 'unicode';
    xecEncoding: Result := 'encoding';
    xecSyntax: Result := 'syntax';
    xecNamespace: Result := 'namespace';
    xecInvalidChar: Result := 'char';
    xecLimit: Result := 'limit';
  else
    Result := IntToStr(Ord(Code));
  end;
end;

{ the fields of a job line }
procedure SplitFields(const Line: string; Fields: TStrings);
var
  I, Start: Integer;
begin
  Fields.Clear;
  Start := 1;
  for I := 1 to Length(Line) + 1 do
    if (I > Length(Line)) or (Line[I] = #9) then
    begin
      Fields.Add(Copy(Line, Start, I - Start));
      Start := I + 1;
    end;
end;

procedure RunInstance(Schema: TLandrixXmlXsdSchemaSet; const Name, FileName: string);
var
  Validator: TLandrixXmlXsdValidator;
begin
  Validator := TLandrixXmlXsdValidator.Create(Schema);
  try
    try
      if Validator.ValidateFile(FileName) then
        Put('instance'#9 + Name + #9'valid')
      else
        Put('instance'#9 + Name + #9'invalid'#9 + Validator.Errors[0].Code + #9 +
          OneLine(Validator.Errors[0].Message));
    except
      on E: ELandrixXmlError do
        Put('instance'#9 + Name + #9'error'#9 + CodeName(E.Code) + #9 + OneLine(E.Message));
      on E: Exception do
        Put('instance'#9 + Name + #9'exception'#9 + E.ClassName + #9 + OneLine(E.Message));
    end;
  finally
    Validator.Free;
  end;
end;

procedure Run(const JobFile: string; FirstGroup: Integer);
var
  Lines, Fields: TStringList;
  Resolver: TLandrixXmlXsdResolver;
  Schema: TLandrixXmlXsdSchemaSet;
  SchemaFile: string;
  Group, I: Integer;
  Skip: Boolean;
begin
  Lines := TStringList.Create;
  Fields := TStringList.Create;
  Resolver := nil;
  Schema := nil;
  try
    Lines.LoadFromFile(JobFile);
    Group := -1;
    Skip := True;
    for I := 0 to Lines.Count - 1 do
    begin
      SplitFields(Lines[I], Fields);
      if Fields[0] = 'group' then
      begin
        Inc(Group);
        Skip := Group < FirstGroup;
        FreeAndNil(Schema);
        FreeAndNil(Resolver);
        Resolver := TLandrixXmlXsdResolver.Create;
        SchemaFile := '';
        if not Skip then
          Put('group'#9 + Fields[1]);
      end
      else if Skip then
        { a group before the first one to run }
      else if Fields[0] = 'schema' then
        SchemaFile := Fields[1]
      else if Fields[0] = 'ns' then
        Resolver.AddNamespace(LandrixXmlStringToUtf8(Fields[1]), Fields[2])
      else if Fields[0] = 'load' then
      begin
        try
          Schema := LandrixXmlXsdLoadSchema(SchemaFile, Resolver);
          Put('schema'#9'ok');
        except
          on E: ELandrixXmlError do
            Put('schema'#9'error'#9 + CodeName(E.Code) + #9 + OneLine(E.Message));
          on E: Exception do
            Put('schema'#9'exception'#9 + E.ClassName + #9 + OneLine(E.Message));
        end;
      end
      else if Fields[0] = 'instance' then
      begin
        if Schema <> nil then
          RunInstance(Schema, Fields[1], Fields[2]);
      end
      else if Fields[0] = 'end' then
        Put('done');
    end;
  finally
    Schema.Free;
    Resolver.Free;
    Fields.Free;
    Lines.Free;
  end;
end;

var
  FirstGroup: Integer;
begin
  if (ParamCount < 2) or (ParamCount > 3) then
  begin
    WriteLn('Usage: LandrixXmlXsts <job-file> <result-file> [first-group]');
    Halt(2);
  end;
  FirstGroup := 0;
  if ParamCount = 3 then
    FirstGroup := StrToInt(ParamStr(3));
  Output := TFileStream.Create(ParamStr(2), fmCreate);
  try
    Run(ParamStr(1), FirstGroup);
  finally
    Output.Free;
  end;
end.
