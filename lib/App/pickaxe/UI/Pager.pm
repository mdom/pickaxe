package App::pickaxe::UI::Pager;
use Mojo::Base -signatures, App::pickaxe::UI::Base;
use Curses;

sub set_text ( $self, $text ) {
    my @lines = split( "\n", $text );
    $self->set_lines( @lines );
}

sub find_toggle ( $self, $key ) {
    $self->find_active( !$self->find_active );
}

sub render ( $self ) {
    $self->next::method;

    if ( $self->find_active ) {

        my $first_line = $self->current_line;
        my $last_line  = $first_line + $self->maxlines - 1;

        for my $match ( @{ $self->matches } ) {
            next if $match->[0] < $first_line;
            next if $match->[0] > $last_line;
            chgat(
                $match->[0] - $first_line + 1,
                @$match[ 1, 2 ],
                A_REVERSE, 0, 0
            );
        }
    }

}

1;
