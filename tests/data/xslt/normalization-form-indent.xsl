<?xml version="1.0" encoding="UTF-8"?>
<!-- normalization-form NFKC with indent: xml:space and the length of the
     start tag are taken after normalization -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output indent="yes" normalization-form="NFKD"/>
  <xsl:template match="/">
    <out><s xml:space="ｐｒｅｓｅｒｖｅ"><a/><b/></s><w a="ﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃﬃ" b="x"/></out>
  </xsl:template>
</xsl:stylesheet>
