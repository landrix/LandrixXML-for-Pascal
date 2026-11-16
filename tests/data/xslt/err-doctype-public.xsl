<?xml version="1.0" encoding="UTF-8"?>
<!-- doctype-public with a character that is no PubidChar -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output doctype-system="s.dtd" doctype-public="a&lt;b"/>
  <xsl:template match="/"><r/></xsl:template>
</xsl:stylesheet>
