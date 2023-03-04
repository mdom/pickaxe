package App::pickaxe::Format;
use Mojo::Base -base, -signatures;

has identifier => sub { {} };
has format     => '';

has _format => sub ($self) {
    my $format     = $self->format;
    my $printf_fmt = '';
    my @subs;

    while (1) {
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
        elsif ( $format =~ /\G([^%]+)/gc ) {
            $printf_fmt .= $1;
        }
        elsif ( $format =~ /\G$/gc ) {
            last;
        }
    }
    return [ $printf_fmt, @subs ];
};

sub printf ( $self, $o ) {
    my ( $fmt, @subs ) = @{ $self->_format };
    return sprintf( $fmt, map { $_->($o) } @subs );
}

1;
