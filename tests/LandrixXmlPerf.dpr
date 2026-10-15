{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Performance measurement (plan step 8): writes a synthetic GAEB-like
  document of about SizeMB megabytes with the streaming writer, then reads
  it with the pull reader, loads it into the DOM and saves the DOM again.
  Prints the times in milliseconds. Peak memory is measured from outside
  (tools/perf.ps1).

  Usage: LandrixXmlPerf [SizeMB] [phase]
    phase: all (default), reader, dom }

program LandrixXmlPerf;

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

const
  GaebNs = 'http://www.gaeb.de/GAEB_DA_XML/DA84/3.2';

function Ms(Start: TDateTime): Integer;
begin
  Result := Integer(Round((Now - Start) * 24 * 60 * 60 * 1000));
end;

function Num(I: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(I));
end;

function U8(const S: AnsiString): TLandrixXmlUtf8;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then
    Move(PAnsiChar(S)^, PAnsiChar(Result)^, Length(S));
end;

{ One item is about 600 bytes. }
function Generate(SizeMB: Integer): TLandrixXmlUtf8;
var
  W: TLandrixXmlWriter;
  I, Items: Integer;
begin
  Items := SizeMB * 1024 * 1024 div 600;
  W := TLandrixXmlWriter.Create;
  try
    W.Indent := True;
    W.StartElementNs(GaebNs, '', 'GAEB');
    W.StartElement('Award');
    W.StartElement('BoQ');
    W.StartElement('BoQBody');
    for I := 1 to Items do
    begin
      W.StartElement('Item');
      W.AttributeUtf8('ID', U8('I') + Num(I));
      W.AttributeUtf8('RNoPart', Num(I mod 1000));
      W.ElementUtf8('Qty', '12.500');
      W.ElementUtf8('QU', 'm2');
      W.StartElement('Description');
      W.StartElement('CompleteText');
      W.StartElement('DetailTxt');
      W.StartElement('Text');
      W.StartElement('p', True);
      W.StartElement('span');
      W.AttributeUtf8('style', 'font-family:Arial;font-size:10pt;');
      W.TextUtf8('Mauerwerk aus Kalksandstein, Wanddicke 24 cm, inklusive Moertel ');
      W.EndElement;
      W.TextUtf8(' und Zubehoer, Position ');
      W.TextUtf8(Num(I));
      W.EndElement;
      W.EndElement;
      W.EndElement;
      W.EndElement;
      W.ElementUtf8('OutlineText', 'Mauerwerk KS 24 cm');
      W.EndElement;
      W.ElementUtf8('UP', '87.35');
      W.EndElement;
    end;
    W.EndElement;
    W.EndElement;
    W.EndElement;
    W.EndElement;
    W.EndDocument;
    Result := W.AsUtf8;
  finally
    W.Free;
  end;
end;

var
  SizeMB, Tokens: Integer;
  Phase: string;
  Xml, Saved: TLandrixXmlUtf8;
  T: TDateTime;
  Reader: TLandrixXmlReader;
  Doc: TLandrixXmlDocument;

begin
  SizeMB := 50;
  Phase := 'all';
  if ParamCount >= 1 then
    SizeMB := StrToInt(ParamStr(1));
  if ParamCount >= 2 then
    Phase := ParamStr(2);

  T := Now;
  Xml := Generate(SizeMB);
  WriteLn('write (streaming writer): ', Length(Xml) div (1024 * 1024), ' MB in ', Ms(T), ' ms');

  if (Phase = 'all') or (Phase = 'reader') then
  begin
    Reader := TLandrixXmlReader.Create;
    try
      T := Now;
      Reader.LoadFromUtf8(Xml);
      Tokens := 0;
      while Reader.Read do
        Inc(Tokens);
      WriteLn('read (pull reader): ', Tokens, ' tokens in ', Ms(T), ' ms');
    finally
      Reader.Free;
    end;
  end;

  if (Phase = 'all') or (Phase = 'dom') then
  begin
    Doc := TLandrixXmlDocument.Create;
    try
      T := Now;
      Doc.LoadFromUtf8(Xml);
      WriteLn('load (DOM): ', Ms(T), ' ms');
      Xml := '';
      T := Now;
      Saved := Doc.SaveToUtf8;
      WriteLn('save (DOM): ', Length(Saved) div (1024 * 1024), ' MB in ', Ms(T), ' ms');
      Saved := '';
      T := Now;
    finally
      Doc.Free;
    end;
    WriteLn('free (DOM): ', Ms(T), ' ms');
  end;
end.
