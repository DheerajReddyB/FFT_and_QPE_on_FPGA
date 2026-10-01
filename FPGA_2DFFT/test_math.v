module test_math;
    real r;
    initial begin
        r = 0.5;
        $display("sin(0.5) = %f", $sin(r));
        $display("cos(0.5) = %f", $cos(r));
        $display("sqrt(0.5) = %f", $sqrt(r));
        $display("atan(0.5) = %f", $atan(r));
        $finish;
    end
endmodule
