def version:
  test("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?\\+?[0-9A-Za-z-]*$")
      or error("Version string does not meet expectations")
;
