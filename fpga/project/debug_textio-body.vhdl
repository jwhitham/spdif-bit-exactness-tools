-- Do-nothing implementation for use in synthesis
package body debug_textio is

    procedure writeline (t: Target; l: inout Line) is
    begin
        null;
    end writeline;

    procedure write (l: inout Line; value: in Integer) is
    begin
        null;
    end write;

    procedure write (l: inout Line; value: in String) is
    begin
        null;
    end write;

    procedure write (l: inout Line; value: in Boolean) is
    begin
        null;
    end write;

    procedure write (l: inout Line; value: in Time) is
    begin
        null;
    end write;

    procedure write (l: inout Line; value: in Real) is
    begin
        null;
    end write;

end debug_textio;
