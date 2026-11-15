<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:formats">
<!-- xsl:result-document without href makes the principal result, with
     the properties of its named format and its own attributes -->
<xsl:output indent="yes"/>
<xsl:output name="f:plain" method="xml" omit-xml-declaration="yes"/>
<xsl:template match="/">
  <xsl:result-document format="f:{'plain'}" indent="{'no'}"><r><a>1</a><b/></r></xsl:result-document>
</xsl:template>
</xsl:stylesheet>
