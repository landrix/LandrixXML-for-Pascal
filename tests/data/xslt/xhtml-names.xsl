<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:h="http://www.w3.org/1999/xhtml">
<!-- method xhtml: names are case-sensitive (HEAD is no head, BR no br),
     a head in the XHTML namespace at any depth gets the content type, a
     meta in it is replaced (one in a head in no namespace is kept), an
     element with a prefix keeps its URI attributes (others are escaped,
     in any namespace and case), an empty processing
     instruction -->
<xsl:output method="xhtml" indent="no"/>
<xsl:template match="/">
  <root>
    <wrap><head xmlns="http://www.w3.org/1999/xhtml"><meta charset="old"/><META http-equiv="Content-Type" content="x"/></head></wrap>
    <head><h:meta http-equiv="Content-Type" content="keep"/></head>
    <h:HEAD><h:title>t</h:title></h:HEAD>
    <h:BR/><h:br/><h:a href="&#xe4;"/><a xmlns="http://www.w3.org/1999/xhtml" href="&#xe4;" HREF="&#xe4;"/><A xmlns="http://www.w3.org/1999/xhtml" href="&#xe4;"/><a href="&#xe4;"/>
    <xsl:processing-instruction name="foo"/>
  </root>
</xsl:template>
</xsl:stylesheet>
