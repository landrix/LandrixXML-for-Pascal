<?xml version="1.0" encoding="UTF-8"?>
<!-- document() with a second argument: the base URI of that node for
     every relative URI (the source document's, then that of a node with
     xml:base pointing elsewhere: the document is read relative to it). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out>
      <xsl:copy-of select="document('xml-base-results.xml', /)"/>
      <xsl:copy-of select="document(('xml-base-copy.xml', 'xml-base-copy.xml'), doc/at)/r/e"/>
      <n><xsl:value-of select="count(document((), /))"/></n>
    </out>
  </xsl:template>
</xsl:stylesheet>
