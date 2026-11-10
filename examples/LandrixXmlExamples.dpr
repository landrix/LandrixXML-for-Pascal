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
  LandrixXmlConvert,
  LandrixXmlSchematron,
  LandrixXmlXsdSchema,
  LandrixXmlXsdSchemaLoader,
  LandrixXmlXsdValidator,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval;

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
        else
          { text, comments, ...: nothing to do }
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

{ --- Schematron validation ---------------------------------------------- }

const
  InvoiceSchematron =
    '<schema xmlns="http://purl.oclc.org/dsdl/schematron" queryBinding="xslt2">' +
    '<ns prefix="inv" uri="' + NsInvoice + '"/><ns prefix="cbc" uri="' + NsCbc + '"/>' +
    '<pattern id="dates"><rule context="/inv:Invoice">' +
    '<assert id="R-1" flag="fatal" test="cbc:DueDate">The due date is missing.</assert>' +
    '<report id="R-2" flag="warning" test="cbc:IssueDate &gt; ''2026-06-30''">' +
    'Issued on <value-of select="cbc:IssueDate"/>.</report>' +
    '</rule></pattern></schema>';

procedure SaveText(const FileName: string; const Text: TLandrixXmlUtf8);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Text[1], Length(Text));
  finally
    Stream.Free;
  end;
end;

procedure ValidateInvoice(const Xml: TLandrixXmlUtf8);
const
  SchFile = 'landrixxml-example-invoice.sch';
var
  Rules: TLandrixXmlSchematronRules;
  Validator: TLandrixXmlSchematronValidator;
  Doc: TLandrixXmlDocument;
  Valid: Boolean;
begin
  { never overwrite a file of the same name }
  if FileExists(SchFile) then
  begin
    Expect(False, SchFile + ' exists already');
    Exit;
  end;
  Rules := TLandrixXmlSchematronRules.Create;
  Validator := nil;
  Doc := TLandrixXmlDocument.Create;
  try
    SaveText(SchFile, LandrixXmlStringToUtf8(InvoiceSchematron));
    Rules.LoadFromSchematronFile(SchFile);   { e.g. 'invoice.sch' }
    Validator := TLandrixXmlSchematronValidator.Create(Rules);
    Doc.LoadFromUtf8(Xml);              { or Validator.ValidateFile('invoice.xml') }
    Valid := Validator.ValidateDocument(Doc);
    { not valid, not incomplete: the fatal R-1 failed; R-2 is only a warning }
    Expect(not Valid and not Validator.Incomplete, 'invalid invoice');
    Expect(Validator.ResultCount = 2, 'two results');
    Expect((Validator.Results[0].Kind = xsrFailedAssert) and (Validator.Results[0].Id = 'R-1') and
      (Validator.Results[0].Flag = 'fatal') and (Validator.Results[0].Location = '/Q{' + NsInvoice + '}Invoice[1]'),
      'failed assert');
    Expect((Validator.Results[1].Kind = xsrSuccessfulReport) and
      (Validator.Results[1].Message = 'Issued on 2026-10-15.'), 'report');
  finally
    Doc.Free;
    Validator.Free;
    Rules.Free;
    DeleteFile(SchFile);
  end;
end;

{ --- validating with an XML Schema --------------------------------------- }

const
  NsOrder = 'urn:example:order';

  OrderSchema =
    '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="' + NsOrder + '"' +
    ' xmlns="' + NsOrder + '" elementFormDefault="qualified">' +
    '<xs:element name="Order"><xs:complexType><xs:sequence>' +
    '<xs:element name="ID" type="xs:string"/>' +
    '<xs:element name="Date" type="xs:date"/>' +
    '<xs:element name="Item" maxOccurs="unbounded"><xs:complexType><xs:sequence>' +
    '<xs:element name="Name" type="xs:string"/>' +
    '<xs:element name="Qty" type="xs:decimal"/>' +
    '</xs:sequence></xs:complexType></xs:element>' +
    '</xs:sequence></xs:complexType></xs:element></xs:schema>';

  { 30 February does not exist, and "two" is no decimal }
  WrongOrder =
    '<Order xmlns="' + NsOrder + '">'#10 +
    '  <ID>A-17</ID>'#10 +
    '  <Date>2026-02-30</Date>'#10 +
    '  <Item><Name>Screws</Name><Qty>two</Qty></Item>'#10 +
    '</Order>';

  GoodOrder =
    '<Order xmlns="' + NsOrder + '">' +
    '<ID>A-18</ID><Date>2026-03-02</Date>' +
    '<Item><Name>Screws</Name><Qty>12.5</Qty></Item>' +
    '<Item><Name>Nuts</Name><Qty>3</Qty></Item>' +
    '</Order>';

procedure ValidateOrder;
const
  XsdFile = 'landrixxml-example-order.xsd';
var
  Schema: TLandrixXmlXsdSchemaSet;
  Validator: TLandrixXmlXsdValidator;
  Doc: TLandrixXmlDocument;
  Valid: Boolean;
  I: Integer;
  Codes: string;
begin
  { never overwrite a file of the same name }
  if FileExists(XsdFile) then
  begin
    Expect(False, XsdFile + ' exists already');
    Exit;
  end;
  Schema := nil;
  Validator := nil;
  Doc := TLandrixXmlDocument.Create;
  try
    SaveText(XsdFile, LandrixXmlStringToUtf8(OrderSchema));
    { an invalid schema raises ELandrixXmlXsdSchemaError (ConstraintCode,
      SchemaFile, Line, Column) }
    Schema := LandrixXmlXsdLoadSchema(XsdFile);   { e.g. 'order.xsd' }
    Validator := TLandrixXmlXsdValidator.Create(Schema);
    Doc.LoadFromString(WrongOrder);
    Valid := Validator.ValidateDocument(Doc);   { or ValidateFile('order.xml') }
    Codes := '';
    for I := 0 to Validator.ErrorCount - 1 do
    begin
      { Line 3, Column 3 (DOM: where the element starts),
        cvc-datatype-valid.1.2.1, "'2026-02-30' is not a valid value for
        'date'." }
      Codes := Codes + IntToStr(Validator.Errors[I].Line) + ':' + Validator.Errors[I].Code + ' ';
    end;
    Expect(not Valid and (Codes = '3:cvc-datatype-valid.1.2.1 3:cvc-type.3.1.3 ' +
      '4:cvc-datatype-valid.1.2.1 4:cvc-type.3.1.3 '), 'schema errors');
    Doc.LoadFromString(GoodOrder);
    Expect(Validator.ValidateDocument(Doc) and (Validator.ErrorCount = 0), 'valid order');
  finally
    Doc.Free;
    Validator.Free;
    Schema.Free;
    DeleteFile(XsdFile);
  end;
end;

{ --- querying with XPath ------------------------------------------------- }

procedure QueryOrder;
var
  Tree: TLandrixXmlXPathTree;
  Context: TLandrixXmlXPathStaticContext;
  Total, Names: TLandrixXmlXPathExpression;
  Evaluator: TLandrixXmlXPathEvaluator;
  Found: TLandrixXmlXPathResult;
begin
  Tree := TLandrixXmlXPathTree.Create;
  Context := TLandrixXmlXPathStaticContext.Create;
  Total := nil;
  Names := nil;
  Evaluator := nil;
  Found := nil;
  try
    Tree.LoadFromUtf8(LandrixXmlStringToUtf8(GoodOrder));   { or LoadFromFile, LoadFromDocument }
    Context.AddNamespace('o', NsOrder);
    { compiled once, evaluated as often as needed; errors raise
      ELandrixXmlXPathError with the XPath error code }
    Total := TLandrixXmlXPathExpression.Create('sum(/o:Order/o:Item/o:Qty)', Context);
    Names := TLandrixXmlXPathExpression.Create('/o:Order/o:Item[o:Qty > 5]/o:Name', Context);
    Evaluator := TLandrixXmlXPathEvaluator.Create(Tree);
    { node 0 is the document node }
    Expect(Evaluator.EvaluateString(Total, 0) = '15.5', 'XPath sum');
    Found := Evaluator.Evaluate(Names, 0);
    Expect((Found.Count = 1) and (Found.StringValueUtf8(0) = 'Screws'), 'XPath nodes');
  finally
    Found.Free;
    Evaluator.Free;
    Names.Free;
    Total.Free;
    Context.Free;
    Tree.Free;
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
  ValidateInvoice(WriteInvoice);
  ValidateOrder;
  QueryOrder;
  HandleErrors;
  if Failures = 0 then
    WriteLn('all examples ok');
  ExitCode := Failures;
end.
