-- Working implementation for use in test benches
package body debug_textio is

    procedure writeline (t: Target; l: inout Line) is
    begin
        std.textio.writeline(std.textio.output, l);
    end writeline;

    procedure write (l: inout Line; value: in Integer) is
    begin
        std.textio.write(l, value);
    end write;

    procedure write (l: inout Line; value: in String) is
    begin
        std.textio.write(l, value);
    end write;

    procedure write (l: inout Line; value: in Boolean) is
    begin
        std.textio.write(l, value);
    end write;

    procedure write (l: inout Line; value: in Time) is
    begin
        std.textio.write(l, value);
    end write;

    procedure write (l: inout Line; value: in Real) is
    begin
        std.textio.write(l, value);
    end write;

end debug_textio;
