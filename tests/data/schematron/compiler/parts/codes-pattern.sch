<?xml version="1.0" encoding="UTF-8"?>
<pattern xmlns="http://purl.oclc.org/dsdl/schematron" id="C">
  <rule context="p:a">
    <let name="v" value="@code"/>
    <assert id="C1" flag="fatal" test="string-length($v)=0 or document('codes.xml')/codes/cl[@id=1]/enumeration[@value=$v]">code <value-of select="$v"/> is not allowed</assert>
    <report id="C2" flag="information" test="count(document((: the list :) 'codes.xml')//enumeration) = 3 and not(document (: an element :) = 'x')">three codes</report>
  </rule>
</pattern>
