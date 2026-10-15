{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  The examples from README.md as one program, so they stay compilable.
  Exit code 0 = every example produced the expected result. }

program LandrixXmlExamples;

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
  LandrixXmlDom,
  LandrixXmlConvert;

const
  NsInvoice = 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2';
  NsCbc = 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2';
  NsCac = 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2';
  NsGaeb = 'http://www.gaeb.de/GAEB_DA_XML/DA86/3.3';

var
  Failures: Integer;

procedure Expect(Ok: Boolean; const Name: string);
begin
  if not Ok then
  begin
    WriteLn('FAIL ', Name);
    Inc(Failures);
  end;
end;

{ --- writing an invoice with the streaming writer ------------------------ }

function WriteInvoice: TLandrixXmlUtf8;
var
  Writer: TLandrixXmlWriter;
begin
  Writer := TLandrixXmlWriter.Create;   { or CreateFile('invoice.xml') }
  try
    Writer.Indent := True;
    Writer.StartElementNs(NsInvoice, '', 'Invoice');
    Writer.DeclareNamespace('cac', NsCac);
    Writer.DeclareNamespace('cbc', NsCbc);
    Writer.ElementUtf8('cbc:ID', 'R-2026-0042');
    Writer.ElementUtf8('cbc:IssueDate', LandrixXmlFormatDate(EncodeDate(2026, 10, 15)));
    Writer.StartElement('cac:LegalMonetaryTotal');
    Writer.StartElement('cbc:PayableAmount');
    Writer.AttributeUtf8('currencyID', 'EUR');
    Writer.TextUtf8(LandrixXmlFormatCurrency(119, 2));
    Writer.EndElement;
    Writer.EndElement;
    Writer.EndElement;
    Writer.EndDocument;
    Result := Writer.AsUtf8;
  finally
    Writer.Free;
  end;
end;

{ --- reading it back with the pull reader ------------------------------- }

procedure ReadInvoice(const Xml: TLandrixXmlUtf8);
var
  Reader: TLandrixXmlReader;
  InTotal: Boolean;
  Number: string;
  Amount: Currency;
  Issued: TDateTime;
begin
  Number := '';
  Amount := 0;
  Issued := 0;
  InTotal := False;
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromUtf8(Xml);         { or LoadFromFile('invoice.xml') }
    while Reader.Read do
      case Reader.TokenType of
        xttStartElement:
          if Reader.NamespaceUriUtf8 = NsCbc then
          begin
            if Reader.LocalNameUtf8 = 'ID' then
              Number := Reader.ReadElementText   { the text inside }
            else if Reader.LocalNameUtf8 = 'IssueDate' then
              Issued := LandrixXmlParseDate(Reader.ReadElementTextUtf8)
            else if InTotal and (Reader.LocalNameUtf8 = 'PayableAmount') then
              Amount := LandrixXmlParseCurrency(Reader.ReadElementTextUtf8);
          end
          else if (Reader.NamespaceUriUtf8 = NsCac) and
            (Reader.LocalNameUtf8 = 'LegalMonetaryTotal') then
            InTotal := True;
        xttEndElement:
          if Reader.LocalNameUtf8 = 'LegalMonetaryTotal' then
            InTotal := False;
      end;
  finally
    Reader.Free;
  end;
  Expect(Number = 'R-2026-0042', 'invoice number');
  Expect(Amount = 119, 'payable amount');
  Expect(Issued = EncodeDate(2026, 10, 15), 'issue date');
end;

{ --- reading GAEB long texts (mixed content) with the DOM --------------- }

procedure ReadLongTexts;
const
  Xml = '<GAEB xmlns="' + NsGaeb + '"><Award><BoQ><BoQBody>' +
    '<Item ID="1"><Qty>12.500</Qty><Description><CompleteText><DetailTxt><Text>' +
    '<p>Mauerwerk <span style="font-weight:bold">KS</span> 24 cm</p>' +
    '</Text></DetailTxt></CompleteText></Description></Item>' +
    '</BoQBody></BoQ></Award></GAEB>';
var
  Doc: TLandrixXmlDocument;
  Body, Item, Text: TLandrixXmlNode;
  Qty: Double;
  LongText: string;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.LoadFromString(Xml);            { or LoadFromFile('bill.x86') }
    Body := Doc.Root.FindChild(NsGaeb, 'Award').FindChild(NsGaeb, 'BoQ')
      .FindChild(NsGaeb, 'BoQBody');
    Item := Body.FirstChildElement;
    while Item <> nil do
    begin
      Qty := LandrixXmlParseDouble(Item.ChildTextUtf8(NsGaeb, 'Qty'));
      Text := Item.FindDescendant(NsGaeb, 'Text');
      LongText := Text.Text;            { all text of the paragraphs and spans }
      Expect(Item.AttributeValue('', 'ID') = '1', 'item ID');
      Expect(Qty = 12.5, 'quantity');
      Expect(LongText = 'Mauerwerk KS 24 cm', 'long text');
      Item := Item.NextSiblingElement;
    end;
  finally
    Doc.Free;
  end;
end;

{ --- building and saving a document with the DOM ------------------------ }

function BuildDocument: TLandrixXmlUtf8;
var
  Doc: TLandrixXmlDocument;
  Root, Item: TLandrixXmlNode;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    Doc.Indent := True;
    Doc.LineBreak := xlbCRLF;
    Root := Doc.AddElement(NsGaeb, '', 'GAEB');
    Item := Root.AddElement('Award').AddElement('Item');
    Item.SetAttribute('ID', '1');
    Item.AddElement('Qty').TextUtf8 := LandrixXmlFormatDouble(12.5, 3);
    Result := Doc.SaveToUtf8;           { or SaveToFile('bill.x86') }
  finally
    Doc.Free;
  end;
end;

{ --- errors ------------------------------------------------------------- }

procedure HandleErrors;
var
  Doc: TLandrixXmlDocument;
  Seen: Boolean;
begin
  Seen := False;
  Doc := TLandrixXmlDocument.Create;
  try
    try
      Doc.LoadFromString('<Invoice><ID>1</Invoice>');
    except
      on E: ELandrixXmlError do
      begin
        { E.Code = xecSyntax, E.Line = 1, E.Column = 17 (the wrong end tag name) }
        Seen := (E.Code = xecSyntax) and (E.Line = 1) and (E.Column = 17);
      end;
    end;
  finally
    Doc.Free;
  end;
  Expect(Seen, 'error with position');
end;

var
  Xml: TLandrixXmlUtf8;

begin
  Failures := 0;
  Xml := WriteInvoice;
  ReadInvoice(Xml);
  ReadLongTexts;
  Xml := BuildDocument;
  Expect(Pos('<Qty>12.500</Qty>', LandrixXmlUtf8ToString(Xml)) > 0, 'built document');
  HandleErrors;
  if Failures = 0 then
    WriteLn('all examples ok');
  ExitCode := Failures;
end.
