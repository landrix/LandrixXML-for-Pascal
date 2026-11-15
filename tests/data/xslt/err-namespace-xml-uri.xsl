<?xml version="1.0" encoding="UTF-8"?>
<!-- XTDE0925: the XML namespace with another prefix. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out><xsl:namespace name="p">http://www.w3.org/XML/1998/namespace</xsl:namespace></out>
  </xsl:template>
</xsl:stylesheet>
