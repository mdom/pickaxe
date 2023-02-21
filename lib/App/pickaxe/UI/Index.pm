package App::pickaxe::UI::Index;
use Mojo::Base -signatures, App::pickaxe::UI::Base;
use Curses;

sub keybindings ($self) {
    return {
        '<End>'      => 'last_item',
        '<Home>'     => 'first_item',
        '<Down>'     => 'next_item',
        '<Up>'       => 'prev_item',
        j            => 'next_item',
        k            => 'prev_item',
        '<PageDown>' => 'next_screen',
        '<PageUp>'   => 'prev_page',
        '<Left>'     => 'prev_page',
        '<Right>'    => 'next_screen',
        '<Space>'    => 'next_screen',
        '<Resize>'   => 'render',
        s            => 'search',
        '/'          => 'find',
        '<Esc>/'     => 'find_reverse',
        'n'          => 'find_next',
        'N'          => 'find_next_reverse',
        '?'          => 'display_help',
        q            => 'quit',
        1            => 'jump',
        2            => 'jump',
        3            => 'jump',
        4            => 'jump',
        5            => 'jump',
        6            => 'jump',
        7            => 'jump',
        8            => 'jump',
        9            => 'jump',
        0            => 'jump',
        '^L'         => 'force_render',
    };
}

sub next_item ( $self, $key ) {
    $self->next_line($key);
}

sub prev_item ( $self, $key ) {
    $self->prev_line($key);
}

sub last_item ( $self, $key ) {
    $self->bottom($key);
}

sub first_item ( $self, $key ) {
    $self->top($key);
}

sub first_line_on_page ($self) {
    return int( $self->current_line / $self->maxlines ) * $self->maxlines;
}

sub render ($self) {
    $self->next::method;
    my $offset = $self->first_line_on_page;
    chgat( $self->current_line - $offset + 1, 0, -1, A_REVERSE, 0, 0 );
}

sub set_lines ( $self, @lines ) {
    my $i = 0;
    @lines = map { sprintf( "%4d %s", ++$i, $_ ) } @lines;
    $self->next::method(@lines);
}

sub bottom ( $self, $key ) {
    $self->goto_line( $self->nlines );
}

1;
