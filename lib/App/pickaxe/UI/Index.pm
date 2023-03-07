package App::pickaxe::UI::Index;
use Mojo::Base -signatures, App::pickaxe::UI::Base;
use Curses;

sub keybindings ($self) {
    return {
        '<End>'      => 'bottom',
        '<Home>'     => 'top',
        '<Down>'     => 'next_line',
        '<Up>'       => 'prev_line',
        j            => 'next_line',
        k            => 'prev_line',
        '<PageDown>' => 'next_screen',
        '<PageUp>'   => 'prev_page',
        '<Left>'     => 'prev_page',
        '<Right>'    => 'next_screen',
        '<Space>'    => 'next_screen',
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

sub first_line_on_page ($self) {
    return int( $self->current_line / $self->maxlines ) * $self->maxlines;
}

sub render ($self) {
    $self->next::method;
    return if $self->empty;
    my $offset = $self->first_line_on_page;
    chgat( $self->current_line - $offset + 1, 0, -1, A_REVERSE, 0, 0 );
}

sub set_lines ( $self, @lines ) {
    my $i = 0;
    $self->next::method(@lines);
}

sub bottom ( $self, $key ) {
    $self->goto_line( $self->nlines );
}

1;
