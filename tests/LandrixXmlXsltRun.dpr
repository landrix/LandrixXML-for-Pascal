{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Helper of tools/xslt-crosscheck.py: runs one XSLT transformation and
  writes the serialized result, for the driver to compare with Saxon's.
  Usage:
    LandrixXmlXsltRun <stylesheet> <source|-> <output> [option ...]
  Options:
    -it NAME          the initial template (Clark name)
    -p NAME=VALUE     a parameter as xs:untypedAtomic
    -d NAME=FILE      a parameter: the document node of FILE
  "-" as source: no source document. Exit code 0 and nothing on the
  console when the transformation succeeded; otherwise exit code 1 and
  one line "error CODE MESSAGE" (an XPath or XSLT error) or "exception
  CLASS MESSAGE". }

program LandrixXmlXsltRun;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXslt;

var
  Sheet: TLandrixXmlXsltStylesheet;
  Transformer: TLandrixXmlXsltTransformer;
  Source, Param: TLandrixXmlXPathTree;
  Output: TFileStream;
  Trees: TObjectList;
  I, K: Integer;
  Option, Name, Value: string;
  Failed: Boolean;

begin
  if ParamCount < 3 then
  begin
    WriteLn('usage: LandrixXmlXsltRun <stylesheet> <source|-> <output> [-it NAME] [-p NAME=VALUE] [-d NAME=FILE]');
    Halt(2);
  end;
  Failed := False;
  Sheet := TLandrixXmlXsltStylesheet.Create;
  Source := nil;
  Transformer := nil;
  Output := nil;
  Trees := TObjectList.Create;
  try
    try
      Sheet.LoadFromFile(ParamStr(1));
      if ParamStr(2) <> '-' then
      begin
        Source := TLandrixXmlXPathTree.Create;
        Source.LoadFromFile(ParamStr(2));
      end;
      Transformer := TLandrixXmlXsltTransformer.Create(Sheet);
      I := 4;
      while I <= ParamCount do
      begin
        Option := ParamStr(I);
        if I + 1 > ParamCount then
          raise Exception.Create('the option ' + Option + ' has no value');
        Value := ParamStr(I + 1);
        Inc(I, 2);
        if Option = '-it' then
        begin
          Transformer.InitialTemplate := LandrixXmlStringToUtf8(Value);
          Continue;
        end;
        K := Pos('=', Value);
        if K < 2 then
          raise Exception.Create('expected NAME=VALUE after ' + Option + ': ' + Value);
        Name := Copy(Value, 1, K - 1);
        Value := Copy(Value, K + 1, MaxInt);
        if Option = '-p' then
          Transformer.SetParameter(LandrixXmlStringToUtf8(Name), LandrixXmlStringToUtf8(Value))
        else if Option = '-d' then
        begin
          Param := TLandrixXmlXPathTree.Create;
          Trees.Add(Param);
          Param.LoadFromFile(Value);
          Transformer.SetParameterTree(LandrixXmlStringToUtf8(Name), Param);
        end
        else
          raise Exception.Create('unknown option ' + Option);
      end;
      Output := TFileStream.Create(ParamStr(3), fmCreate);
      Transformer.Transform(Source, Output);
    except
      on E: ELandrixXmlXPathError do
      begin
        WriteLn('error ', E.XPathCode, ' ', E.Message);
        Failed := True;
      end;
      on E: Exception do
      begin
        WriteLn('exception ', E.ClassName, ' ', E.Message);
        Failed := True;
      end;
    end;
  finally
    Output.Free;
    Transformer.Free;
    Source.Free;
    Trees.Free;
    Sheet.Free;
  end;
  if Failed then
    Halt(1);
end.
