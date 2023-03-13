package App::pickaxe::Format;
use Mojo::Base -base, -signatures;
use Curses;
use POSIX 'strftime';

has identifier => sub { {} };
has format     => '';
has 'cols';

sub format_time ( $time, $strftime_fmt ) {
    my ( $year, $mon, $mday, $hour, $min, $sec ) =
      $time =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;

    ## The %{} syntax was used with something that wasn't a time
    return $time if not defined $year;

    $mon  -= 1;
    $year -= 1900;
    strftime( $strftime_fmt, $sec, $min, $hour, $mday, $mon, $year );
}

has _format => sub ($self) {
    my $format     = $self->format;
    my $printf_fmt = '';
    my @subs;

    while ( $format !~ /\G$/gc ) {
        if ( $format =~ /\G%(-?\d+(?:.\d)?)?(?:{(.*?)})?([a-zA-Z])/gc ) {
            my ( $mod, $time_fmt, $format ) = ( $1, $2, $3 );
            $mod //= '';
            if ( my $sub = $self->identifier->{$format} ) {
                $printf_fmt .= "%${mod}s";
                if ($time_fmt) {
                    push @subs, sub ($o) {
                        format_time( $sub->($o), $time_fmt );
                    };
                }
                else {
                    push @subs, $sub;
                }
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
        elsif ( $format =~ /\G(%%)/gc ) {
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
