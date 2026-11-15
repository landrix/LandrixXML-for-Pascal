<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0430: the excluded p is urn:old; the element's p (urn:new) is a
     namespace node that xsl:namespace binds otherwise. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:old" exclude-result-prefixes="p">
  <xsl:template match="/">
    <p:r xmlns:p="urn:new"><xsl:namespace name="p">urn:other</xsl:namespace></p:r>
  </xsl:template>
</xsl:stylesheet>
