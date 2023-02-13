package App::pickaxe::Pages;
use Mojo::Base -signatures, -base;

has index => 0;
has array => sub { [] };

has 'order' => 'reverse_updated_on';

sub sort ($self, $order) {

    my $current = $self->current;

    $self->order($order);
    $self->set($self->array);

    for ( my $i = 0; $i < @{$self->array}; $i++ ) {
        if ($current == $self->array->[$i] ) {
            $self->index( $i );
            last;
        }
    }
}

sub current ($self, $page = undef) {
    $self->array->[ $self->index ] = $page if $page;
    return $self->array->[ $self->index ];
}

sub delete_current ( $self ) {
    delete $self->array->[ $self->index ];
}

sub set ( $self, $pages ) {

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->array( $pages );

    if ( $self->index >= $self->count ) {
        $self->index( $self->count - 1 );
    }
    return $self;
}

sub next ( $self ) {
    $self->set_index( $self->index + 1 );
}

sub prev ( $self ) {
    $self->set_index( $self->index + -1 );
}

sub set_index ( $self, $index ) {
    $self->index( $index );
    if ( $index < 0 ) {
        $self->index(0);
    }
    elsif ( $self->index >= $self->count ) {
        $self->index( $self->count - 1 );
    }
}

sub count ( $self ) {
    scalar $self->array->@*;
}

sub each ( $self ) {
    $self->array->@*;
}

sub empty ( $self ) {
    $self->count == 0;
}

1;
