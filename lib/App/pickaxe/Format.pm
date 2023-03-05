package App::pickaxe::Format;
use Mojo::Base -base, -signatures;
use Curses;

has identifier => sub { {} };
has format     => '';
has 'cols';

has _format => sub ($self) {
    my $format     = $self->format;
    my $printf_fmt = '';
    my @subs;

    while ( $format !~ /\G$/gc ) {
        if ( $format =~ /\G%(-?\d+(?:.\d)?)?([a-zA-Z])/gc ) {
            my ( $mod, $format ) = ( $1, $2 );
            $mod //= '';
            if ( my $i = $self->identifier->{$format} ) {
                $printf_fmt .= "%${mod}s";
                push @subs, $i;
            }
            else {
                die "Unknown format specifier <$format>\n";
            }
        }
        elsif ( $format =~ /\G%([>*].)/gc ) {
            $printf_fmt .= "%%$1";
        }
        elsif ( $format =~ /\G([^%]+)/gc ) {
            $printf_fmt .= $1;
        }
    }
    return [ $printf_fmt, @subs ];
};

sub printf ( $self, $o ) {
    my ( $fmt, @subs ) = @{ $self->_format };
    my $cols = $self->cols || $COLS;

    my $result = sprintf( $fmt, map { $_->($o) } @subs );

    if ( $result =~ /^(.*?)%>(.)(.*)$/ ) {
        my ( $l1, $l3 ) = ( length($1), length($3) );
        if ( $l1 >= $cols ) {
            $result = substr( $1, 0, $cols );
        }
        elsif ( $l1 + $l3 > $cols ) {
            $result = substr( $1 . $3, 0, $cols );
        }
        else {
            $result = $1 . ( $2 x ( $cols - $l1 - $l3 ) ) . $3;
        }
    }
    elsif ( $result =~ /^(.*?)%\*(.)(.*)$/ ) {
        my ( $l1, $l3 ) = ( length($1), length($3) );
        if ( $l3 >= $cols ) {
            $result = substr( $3, 0, $cols );
        }
        elsif ( $l1 + $l3 > $cols ) {
            $result = substr( $1, 0, $cols - $l3 ) . $3;
        }
        else {
            $result = $1 . ( $2 x ( $cols - $l1 - $l3 ) ) . $3;
        }
    }
    else {
        $result = substr( $result, 0, $cols );
    }
    return $result;
}

1;
