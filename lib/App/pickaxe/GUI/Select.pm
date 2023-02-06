package App::pickaxe::GUI::Select;
use Mojo::Base -signatures, App::pickaxe::GUI::Scrollable;
use Curses;

sub set_text ( $self, $text ) {
    my @lines = split( "\n", $text );
    $self->set_lines( @lines );
}

sub render( $self ) {
    $self->next::method;
    my $offset = $self->first_line_on_page;
    chgat( $self->current_line - $offset + 1, 0, -1, A_REVERSE, 0, 0 );
}


1;
