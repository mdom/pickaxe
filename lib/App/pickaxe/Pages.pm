package App::pickaxe::Pages;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

has index => 0;
has array => sub { [] };

has 'order' => 'reverse_updated_on';

sub sort ( $self, $order ) {
    $self->order($order);
    $self->set( $self->array );
}

sub switch_to ( $self, $elt ) {
    return if !$elt;
    for ( my $i = 0 ; $i < @{ $self->array } ; $i++ ) {
        if ( $elt->title eq $self->array->[$i]->title ) {
            $self->index($i);
            return 1;
        }
    }
    return;
}

sub current ( $self, $page = undef ) {
    $self->array->[ $self->index ] = $page if $page;
    return $self->array->[ $self->index ];
}

sub add ( $self, $page ) {
    push @{ $self->array }, $page;
    $self->set( $self->array );
    $self->switch_to($page);
}

sub delete_current ($self) {
    splice @{ $self->array }, $self->index, 1;
    $self->index( $self->index - 1 ) if !$self->array->[ $self->index ];
    $self->emit('changed');
}

sub replace_current ( $self, $page ) {
    $self->array->[ $self->index ] = $page;
    $self->set( $self->array );
}

sub set ( $self, $pages ) {

    my $current = $self->current;

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->array($pages);

    ## Always try to preserve the current page the user selected ...
    ## .. if that's not possible select the first
    if ( !$self->switch_to($current) ) {
        $self->index(0);
    }
    $self->emit('changed');

    return $self;
}

sub next ($self) {
    $self->set_index( $self->index + 1 );
}

sub prev ($self) {
    $self->set_index( $self->index + -1 );
}

sub set_index ( $self, $index ) {
    $self->index($index);
    if ( $index < 0 ) {
        $self->index(0);
    }
    elsif ( $self->index >= $self->count ) {
        $self->index( $self->count - 1 );
    }
}

sub count ($self) {
    scalar $self->array->@*;
}

sub each ($self) {
    $self->array->@*;
}

sub empty ($self) {
    $self->count == 0;
}

1;
