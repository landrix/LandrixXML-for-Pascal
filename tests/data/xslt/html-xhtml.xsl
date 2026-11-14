<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:h="http://www.w3.org/1999/xhtml">
<!-- XHTML elements lose their prefix, the declarations of XHTML prefixes
     are left out (Saxon's HTML5 output); head and meta by local name -->
<xsl:output method="html"/>
<xsl:template match="/">
  <h:html><h:head><h:title>t</h:title></h:head><h:body><h:p>x<h:br/></h:p><div><p/></div>
  <x:head xmlns:x="urn:x"/></h:body></h:html>
</xsl:template>
</xsl:stylesheet>
