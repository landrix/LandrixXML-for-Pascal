<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/"><out a="{doc-available('_data.xml')}" m="{doc-available('missing.xml')}"
    d="{doc('_data.xml')/data/@v}" s="{doc('_data.xml') is doc('_data.xml')}" e="{count(document('_data.xml')/data)}"/></xsl:template>
</xsl:stylesheet>
