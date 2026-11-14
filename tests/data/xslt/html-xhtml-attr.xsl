<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:h="http://www.w3.org/1999/xhtml">
<!-- an attribute in the XHTML namespace keeps its prefix, declared unless
     the parent has one with that prefix; elements in no namespace under an XHTML default
     declare xmlns=""; no URI escaping on a prefixed element -->
<xsl:output method="html" indent="no"/>
<xsl:template match="/">
  <h:html h:a="x"><h:body><h:p h:b="y"/><p h:c="z"/><x:p xmlns:x="urn:x" h:d="w"/></h:body></h:html>
  <html xmlns="http://www.w3.org/1999/xhtml"><body><p:r xmlns:p="urn:p"><x/><p:x/></p:r>
  <h:a href="é">x</h:a><a href="é">y</a></body></html>
  <h:div h:a="x"><h:p h:b="y"><h:i h:c="z"/></h:p><span h:c="z"><h:b/></span></h:div>
</xsl:template>
</xsl:stylesheet>
