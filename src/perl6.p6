use Perl6::Grammar;
use Perl6::Actions;
use Perl6::Compiler;


sub MAIN(@ARGS) {
    # Initialize dynops.
    pir::rakudo_dynop_setup__v();

    # Create and configure compiler object.
    my $comp := Perl6::Compiler.new();
    $comp.language('perl6');
    $comp.parsegrammar(Perl6::Grammar);
    $comp.parseactions(Perl6::Actions);
    hll-config($comp.config);
    
    # Add extra command line options.
    my @clo := $comp.commandline_options();
    @clo.push('parsetrace');
    @clo.push('setting=s');
    
    # Enter the compiler.
    $comp.command_line(@ARGS, :encoding('utf8'), :transcode('ascii iso-8859-1'));
}
