-- Working implementation for use in test benches
package debug_textio is

    subtype Line is std.textio.Line;
    type Target is (output);

    procedure writeline (t: Target; l: inout Line);
    procedure write (l: inout Line; value: in Integer);
    procedure write (l: inout Line; value: in String);
    procedure write (l: inout Line; value: in Boolean);
    procedure write (l: inout Line; value: in Time);
    procedure write (l: inout Line; value: in Real);

end debug_textio;
