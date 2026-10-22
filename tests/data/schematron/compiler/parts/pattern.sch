<?xml version="1.0" encoding="UTF-8"?>
<pattern xmlns="http://purl.oclc.org/dsdl/schematron" id="A">
  <rule context="p:a">
    <let name="v" value="xs:integer(@n)"/>
    <assert id="A1" flag="fatal" test="f:size($v) = 'small'">a with   n = '<value-of select="$v"/>' is <value-of select="f:size($v)"/></assert>
  </rule>
</pattern>
