package App::pickaxe::GUI::Select;
use Mojo::Base -signatures, App::pickaxe::GUI::Scrollable;
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

sub bottom ( $self, $key ) {
    $self->goto_line( $self->nlines );
}

1;
