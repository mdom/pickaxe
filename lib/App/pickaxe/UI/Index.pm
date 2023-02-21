package App::pickaxe::UI::Index;
use Mojo::Base -signatures, App::pickaxe::UI::Base;
use Curses;

sub next_item ($self,$key) {
    $self->next_line($key);
}

sub prev_item ($self,$key) {
    $self->prev_line($key);
}

sub last_item ($self,$key) {
    $self->bottom($key);
}

sub first_item ($self,$key) {
    $self->top($key);
}

sub first_line_on_page ($self) {
    return int( $self->current_line / $self->maxlines ) * $self->maxlines;
}

sub render( $self ) {
    $self->next::method;
    my $offset = $self->first_line_on_page;
    chgat( $self->current_line - $offset + 1, 0, -1, A_REVERSE, 0, 0 );
}

sub set_lines ( $self, @lines ) {
    my $i = 0;
    @lines = map { sprintf("%4d %s", ++$i, $_) } @lines;
    $self->next::method(@lines);
}

sub bottom ( $self, $key ) {
    $self->goto_line( $self->nlines );
}

1;
