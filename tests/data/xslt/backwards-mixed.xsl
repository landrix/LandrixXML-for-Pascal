<?xml version="1.0" encoding="UTF-8"?>
<!-- An XSLT 2.0 stylesheet with parts in backwards compatible mode,
     expected output from Saxon HE 12.9: a key with one declaration in that
     mode compares all its values as strings, whatever the mode of the
     caller; a key without one compares typed values also for a caller in
     that mode; the functions of XSLT take the first item of their
     arguments (the base node of document(), the arity of
     function-available(), the value of format-date(), whose picture,
     language, calendar and place are strings unless empty). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
  <xsl:output method="xml" indent="no"/>
  <xsl:key name="mixed" version="1.0" match="none" use="."/>
  <xsl:key name="mixed" match="y" use="1"/>
  <xsl:key name="typed" match="y" use="'1'"/>
  <xsl:template match="/">
    <r>
      <two><xsl:value-of select="count(key('mixed', '1'))"/>|<xsl:value-of select="count(key('typed', 1))"/></two>
      <xsl:call-template name="one"/>
    </r>
  </xsl:template>
  <xsl:template name="one" version="1.0">
    <one><xsl:value-of select="count(key('mixed', '1'))"/>|<xsl:value-of select="count(key('typed', 1))"/>|<xsl:value-of select="count(key('typed', '1'))"/>|<xsl:value-of select="count(document('backwards-mixed.xml', /d/x))"/>|<xsl:value-of select="function-available('count', (1, 2))"/>|<xsl:value-of select="format-date((xs:date('2020-01-01'), xs:date('2021-01-01')), '[Y]')"/>|<xsl:value-of select="format-date(xs:date('2020-01-01'), 1)"/>|<xsl:value-of select="format-date(xs:date('2020-01-01'), '[Y]', (), (), 1)"/></one>
  </xsl:template>
</xsl:stylesheet>
